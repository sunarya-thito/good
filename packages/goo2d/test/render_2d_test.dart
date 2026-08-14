import 'dart:ffi' hide Size;
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late InlineGameHandle run;


// GameRenderer2D, the game-isolate producer: does Renderable2D actually
// register itself (the bug Child/Parent had), does the query include child
// entities (the bug the Without<Child>() stub had), and is the hierarchy
// flattening arithmetically right.
//
// Everything runs on one isolate through start(inline: true, autoTick: false),
// so the test is both the simulation and the consumer of the draw ring. That
// is not a reduced-fidelity stand-in: the bytes checked here are the exact
// bytes that cross to the main isolate in the spawned configuration.

class _Sprite extends EntityStruct
    with Transform2D, WorldTransform2D, Child, Parent, Renderable2D {
  /// One sprite, declared with nothing but the defaults, so every geometry
  /// test below states the size it wants per entity and inherits the default
  /// centred pivot.
  late final Sprite quad;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    quad = descriptor.has();
  }
}

/// Same fields minus Renderable2D - the negative case for the signature bit.
class _Invisible extends EntityStruct with Transform2D, Child {}

/// A bare grouping node: hierarchy links, no transform, nothing to draw.
class _Group extends EntityStruct with Child, Parent {}

/// Two sprites on one entity - a body and a hat - with every field supplied
/// through `has()`'s named parameters and **no `onMounted` anywhere**. Both
/// halves of that matter: that one entity can carry several independently
/// addressed sprites at all, and that declaring them is the whole of the
/// configuration.
class _TwoSprite extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  late final Sprite body;
  late final Sprite hat;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    body = descriptor.has(width: 10, height: 10, color: 0xFF111111);
    hat = descriptor.has(
      width: 4,
      height: 2,
      color: 0xFF222222,
      zIndex: 5,
      // Fraction *and* offset together: "centred, then 6 further up" cannot
      // be said with a fraction of the hat's own 2-unit height alone.
      pivot: const RelativeOffset2D(fractionX: 0.5, fractionY: 0.5, offsetY: 6),
      alignment: const RelativeOffset2D(fractionX: 1, offsetX: 3),
      nineSliceBorder: const NineSliceBorder.all(2),
      visible: true,
    );
  }
}

/// One visible sprite and one declared `visible: false`, on the same entity -
/// so "hidden" can be measured as a missing record rather than as a quad that
/// happens to be transparent.
class _HalfHidden extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  late final Sprite shown;
  late final Sprite hidden;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    shown = descriptor.has(width: 4, height: 4, color: 0xFF00FF00);
    hidden = descriptor.has(width: 4, height: 4, color: 0xFFFF0000, visible: false);
  }
}

/// Two sprites declared *out* of depth order - the high one first - so a pass
/// that merely preserved declaration order would fail the ordering tests.
class _Stack extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  static const int highColor = 0xFFAA0000;
  static const int lowColor = 0xFF0000AA;

  late final Sprite high;
  late final Sprite low;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    high = descriptor.has(width: 2, height: 2, color: highColor, zIndex: 3);
    low = descriptor.has(width: 2, height: 2, color: lowColor, zIndex: 1);
  }
}

/// A sprite pivoted on its own top-left corner instead of its centre.
class _TopLeft extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  late final Sprite quad;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    quad = descriptor.has(
      width: 40,
      height: 20,
      color: 0xFF334455,
      pivot: RelativeOffset2D.zero,
    );
  }
}

/// A camera. An ordinary entity - the renderer finds it by query. `Child` so
/// one of the tests below can parent it to something that moves.
class _Eye extends EntityStruct
    with Transform2D, WorldTransform2D, Child, Camera {}

/// A 2x1 PNG, the same fixture `texture_test.dart` uses. Never decoded here:
/// this suite is the *game-isolate* side, whose whole point is that a texture
/// is an address and nothing more.
final Uint8List _png2x1 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR42mP4z8AAQv8BD/kD'
  '/Zh51wAAAAAASUVORK5CYII=',
);

/// A [Texture] whose decoded image is a landmine.
///
/// The producer is supposed to read a texture's *address* and nothing else -
/// it runs on an isolate with no Flutter engine, where `image` throws by
/// design. This suite runs inline on the main isolate, where the asset really
/// does get decoded by `loadScene`, so "the producer never touches the image"
/// would otherwise be unobservable here: the read would simply succeed. Making
/// the getter throw turns that invariant into something the tick either
/// survives or does not.
class _TrapTexture extends Texture {
  @override
  ui.Image get image => throw StateError(
        'GameRenderer2D read Texture.image. The producer runs on the game '
        'isolate, which has no decoded image to read - it may only write the '
        'address.',
      );
}

class _TrapTextureAsset extends GameAsset<_TrapTexture> {
  @override
  GameAssetSource get source => MemoryImageSource(_png2x1, name: 'trap.png');

  @override
  _TrapTexture createInstance() => _TrapTexture();

  /// Decodes nothing: this asset exists to be *addressed*, and the trap is in
  /// the getter rather than in the load.
  @override
  Future<void> loadInto(_TrapTexture instance) async {}

  @override
  String get debugLabel => 'TrapTexture(trap.png)';
}

/// One sprite with a texture and one without, on the same entity - so "carries
/// the address" and "carries the sentinel" are measured against each other in
/// a single frame rather than in two unrelated scenes.
class _Textured extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  /// Static and shared, the intended style: a `GameAsset` is identity-compared,
  /// so one key is one instance, one address and (on a loading isolate) one
  /// decode, however many prefabs declare it.
  static final _TrapTextureAsset tileAsset = _TrapTextureAsset();

  static const int texturedColor = 0xFF00FF00;
  static const int untexturedColor = 0xFF0000FF;

  late final Texture tile;
  late final Sprite textured;
  late final Sprite plain;

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    // Runs before describeStruct, which is what lets the handle below be a
    // declared row default rather than something an onMounted has to write.
    tile = descriptor.has(tileAsset);
  }

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    textured = descriptor.has(
      texture: tile,
      width: 4,
      height: 4,
      color: texturedColor,
    );
    plain = descriptor.has(width: 4, height: 4, color: untexturedColor, zIndex: 1);
  }
}

/// A texture that declares its source size, which is what makes it
/// nine-sliceable at all - the insets are in source pixels, so the UV split
/// divides by these. 16x16 with a 4px inset gives cuts at 0, 0.25, 0.75, 1,
/// which are exact in binary and so safe to assert on the nose.
class _PanelTexture extends Texture {
  _PanelTexture() : super(sourceWidth: 16, sourceHeight: 16);
}

class _PanelTextureAsset extends GameAsset<_PanelTexture> {
  @override
  GameAssetSource get source => MemoryImageSource(_png2x1, name: 'panel.png');

  @override
  _PanelTexture createInstance() => _PanelTexture();

  /// Never decoded: every assertion below is about geometry the *producer*
  /// computes on the game isolate, which by design never touches an image.
  @override
  Future<void> loadInto(_PanelTexture instance) async {}

  @override
  String get debugLabel => 'PanelTexture(panel.png)';
}

/// A nine-sliced panel: 16x16 source, 4px inset on every edge, drawn 40x40.
///
/// Every number is chosen to stay exact in binary so the expectations below
/// are equalities rather than tolerances.
class _Panel extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  static final _PanelTextureAsset asset = _PanelTextureAsset();
  static const double inset = 4;
  static const double drawSize = 40;

  late final Texture skin;
  late final Sprite frame;

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    skin = descriptor.has(asset);
  }

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    frame = descriptor.has(
      texture: skin,
      width: drawSize,
      height: drawSize,
      // Top-left pivot so the grid lines below are the sprite's own local
      // coordinates, unshifted - the arithmetic under test is the slicing,
      // not the pivot, which has its own tests.
      pivot: RelativeOffset2D.zero,
      nineSliceBorder: const NineSliceBorder.all(inset),
    );
  }
}

/// The same panel drawn smaller than its own insets can fit: 4+4 of border on
/// a 6-unit axis. Exists to pin the collapse behaviour.
class _UnsizedPanel extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  late final Texture skin;
  late final Sprite frame;

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    skin = descriptor.has(_Panel.asset);
  }

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    frame = descriptor.has(
      texture: skin,
      width: 6,
      height: 40,
      pivot: RelativeOffset2D.zero,
      nineSliceBorder: const NineSliceBorder.all(4),
    );
  }
}

/// Insets declared, no texture. Slicing subdivides image space, so with no
/// image there is nothing to subdivide.
class _BorderedUntextured extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  late final Sprite frame;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    frame = descriptor.has(
      width: 40,
      height: 40,
      pivot: RelativeOffset2D.zero,
      nineSliceBorder: const NineSliceBorder.all(4),
    );
  }
}

class _SpriteScene extends SceneStruct {
  /// This fixture's handle, captured when the framework mounts it. Entity
  /// creation lives on `Scene` now - one `SceneStruct` can back several loaded
  /// scenes - and a loaded scene is handed its own handle at mount.
  late Scene handle;

  @override
  void onMounted(Scene scene) => handle = scene;

  Entity addEntity<T extends EntityStruct>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _SpriteScene();

  late final _Sprite sprite;
  late final _Invisible invisible;
  late final _Group group;
  late final _TwoSprite twoSprite;
  late final _HalfHidden halfHidden;
  late final _Stack stack;
  late final _TopLeft topLeft;
  late final _Eye eye;

  /// Registered last on purpose: archetype registration order is the encounter
  /// order the z-sort ties break on, so a new prefab has to go on the end or
  /// it would reshuffle the ordering tests below.
  late final _Textured texturedPair;
  late final _Panel panel;
  late final _UnsizedPanel unsizedPanel;
  late final _BorderedUntextured borderedUntextured;

  @override
  void describeScene(SceneDescriptor descriptor) {
    sprite = descriptor.has(_Sprite());
    invisible = descriptor.has(_Invisible());
    group = descriptor.has(_Group());
    twoSprite = descriptor.has(_TwoSprite());
    halfHidden = descriptor.has(_HalfHidden());
    stack = descriptor.has(_Stack());
    topLeft = descriptor.has(_TopLeft());
    eye = descriptor.has(_Eye());
    texturedPair = descriptor.has(_Textured());
    panel = descriptor.has(_Panel());
    unsizedPanel = descriptor.has(_UnsizedPanel());
    borderedUntextured = descriptor.has(_BorderedUntextured());
  }
}

class _RenderState extends GameState2D<_RenderGame> {
  @override
  void onMounted() {
    loadScene(_SpriteScene());
  }
}

/// `Game2D` + `GameState2D` rather than a hand-declared `GameRenderer2D`, and
/// that is now the only way round. The two halves sit on two isolates: the
/// `Game` declares and allocates the frame buffers and the default camera, the
/// state declares the systems that fill them. `createState` is narrowed to
/// `GameState2D`, so they cannot come apart.
class _RenderGame extends Game2D {
  /// The view under test - this fixture's spelling of `defaultCamera`.
  CameraView get view => defaultCamera;

  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState2D<_RenderGame> createState() => _RenderState();
}

const Duration _step = Duration(milliseconds: 10);

/// One decoded quad, for readable expectations. A test-only convenience -
/// nothing in the pipeline itself ever materializes one of these.
class _Quad {
  _Quad(this.x, this.y, this.color, this.texture, this.u, this.v);
  final List<double> x;
  final List<double> y;
  final int color;

  /// The texture registry address, or [DrawSpriteData2D.noTexture].
  final int texture;

  /// One UV pair per corner, in the same corner order as [x]/[y].
  final List<double> u;
  final List<double> v;

  @override
  String toString() =>
      'Quad(x: $x, y: $y, color: 0x${color.toRadixString(16)}, texture: $texture)';
}

class _Frame {
  _Frame(this.tick, this.quads);
  final int tick;
  final List<_Quad> quads;
}

/// Adds a camera entity **and points it at the game's view**. A camera that
/// occupies no view is nobody's camera now - which is exactly what lets two
/// views look at different things.
Entity _eye(_RenderGame game, _SpriteScene scene, {Entity? parent}) {
  final eye = scene.addEntity(scene.eye, parent: parent);
  // No tick management at all: this runs immediately after the row is
  // created, so its page has never published and the write is allowed - the
  // same path every other field default here takes. Opening a tick would
  // publish the page and make the caller's *next* write assert.
  scene.eye.view[eye] = game.view;
  return eye;
}

List<_Frame> _drainFrames(_RenderGame game) {
  final buffer = run.state.getSystem<GameRenderer2D>().framesFor(game.view).buffer;
  final frames = <_Frame>[];
  // At most one: a handoff buffer holds the newest complete frame, not a
  // backlog. Where this used to loop over a ring drain and could see several,
  // it now sees the latest and nothing older - which is the whole point.
  final slot = buffer.beginRead();
  if (slot != null) {
    final used = buffer.readUsedBytes;
    final payload = slot.asTypedList(used);
    final batch = ByteData.sublistView(payload);
    final quads = <_Quad>[];
    var offset = DrawData2D.batchHeaderBytes;
    final count = const DrawSpriteData2D().itemCount(used);
    for (var i = 0; i < count; i++) {
      quads.add(_Quad(
        [
          for (var c = 0; c < 4; c++)
            batch.getFloat32(offset + c * 8, Endian.little),
        ],
        [
          for (var c = 0; c < 4; c++)
            batch.getFloat32(offset + c * 8 + 4, Endian.little),
        ],
        batch.getUint32(offset + 32, Endian.little),
        batch.getInt32(offset + 36, Endian.little),
        [
          for (var c = 0; c < 4; c++)
            batch.getFloat32(offset + 40 + c * 8, Endian.little),
        ],
        [
          for (var c = 0; c < 4; c++)
            batch.getFloat32(offset + 40 + c * 8 + 4, Endian.little),
        ],
      ));
      offset += DrawSpriteData2D.strideBytes;
    }
    frames.add(_Frame(DrawData2D.batchTick(batch), quads));
  }
  return frames;
}

Future<_RenderGame> _game() async {
  final game = _RenderGame();
  run = await Game.startInline(game);
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

/// Sizes an entity's one sprite so it produces a quad. Safe to call before the
/// first tick: nothing has been published yet, so no `beginTick` will copy over
/// it (see `data_layout.dart`'s `_Field._write`).
void _size(
  _Sprite prefab,
  Entity entity,
  double w,
  double h, [
  int color = 0xFF112233,
  int zIndex = 0,
]) {
  prefab.quad.width[entity] = w;
  prefab.quad.height[entity] = h;
  prefab.quad.color[entity] = color;
  prefab.quad.zIndex[entity] = zIndex;
}

void _place(
  _Sprite prefab,
  Entity entity, {
  double x = 0,
  double y = 0,
  double scaleX = 1,
  double scaleY = 1,
  double rotation = 0,
}) {
  prefab
    ..transformOffsetX[entity] = x
    ..transformOffsetY[entity] = y
    ..transformScaleX[entity] = scaleX
    ..transformScaleY[entity] = scaleY
    ..transformRotation[entity] = rotation;
}

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('Renderable2D registration', () {
    test('sets its own signature bit, so withAll(Renderable2D) discriminates', () async {
      await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final matcher =
          ArchetypeQueryDescriptor().query().withAll(Renderable2D).build();
      // The regression this exists for: without describeType calling
      // component.has<Renderable2D>(), the bit is never OR'd into any
      // archetype's signature, and `matches` returns true for *everything*
      // (required mask 0). Both halves are needed to catch that - the
      // positive case passes either way.
      expect(matcher.matches(scene.sprite.archetype.componentSignature), isTrue);
      expect(matcher.matches(scene.invisible.archetype.componentSignature), isFalse);
    });

    test('declares sane defaults: visible, unsized, opaque white, centred', () async {
      await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final entity = scene.addEntity(scene.sprite);
      final quad = scene.sprite.quad;
      expect(quad.visible[entity], 1);
      expect(quad.width[entity], 0);
      expect(quad.height[entity], 0);
      expect(quad.color[entity], 0xFFFFFFFF);
      expect(quad.zIndex[entity], 0);
      expect(quad.texture[entity], isNull,
          reason: 'no texture is the default - an untextured sprite draws its '
              'colour, and nothing forces a game to declare a placeholder '
              'image to get that');
      expect(quad.pivotFractionX[entity], 0.5);
      expect(quad.pivotFractionY[entity], 0.5,
          reason: 'the default pivot is centred, which is what makes rotation '
              'and scale act about a sprite middle - and what keeps the '
              'hand-computed geometry below unchanged from before pivots '
              'existed');
      expect(quad.pivotOffsetX[entity], 0);
      expect(quad.pivotOffsetY[entity], 0);
      expect(quad.alignFractionX[entity], 0);
      expect(quad.alignFractionY[entity], 0);
      expect(quad.alignOffsetX[entity], 0);
      expect(quad.alignOffsetY[entity], 0);
      expect(quad.borderLeft[entity], 0);
      expect(quad.borderTop[entity], 0);
      expect(quad.borderRight[entity], 0);
      expect(quad.borderBottom[entity], 0,
          reason: 'an all-zero border is NineSliceBorder.none, i.e. a plain '
              'single quad');
    });

    test('several has() calls give several sprites, in declaration order', () async {
      await _game();
      final scene = run.state.getScene<_SpriteScene>();
      expect(scene.twoSprite.sprites, hasLength(2),
          reason: 'sprites is the generic list GameRenderer2D walks - a '
              'consumer that does not know this prefab field names has to be '
              'able to find every sprite through it');
      expect(scene.twoSprite.sprites,
          [scene.twoSprite.body, scene.twoSprite.hat],
          reason: 'in declaration order, which is also the encounter order '
              'z-sorting ties break on');
      expect(scene.sprite.sprites, hasLength(1));
    });

    test('Transform2D defaults to unit scale, not the field default of zero', () async {
      await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final entity = scene.addEntity(scene.sprite);
      // A zero default would collapse every quad to a point - the renderer
      // would produce records that draw nothing at all.
      expect(scene.sprite.transformScaleX[entity], 1);
      expect(scene.sprite.transformScaleY[entity], 1);
    });
  });

  group('record production', () {
    test('one batch per presented frame, stamped with the tick it depicts',
        () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      _size(scene.sprite, scene.addEntity(scene.sprite), 10, 10);

      // One frame, read straight away - the stamp names the tick it depicts.
      run.state.advance(_step);
      expect([for (final f in _drainFrames(game)) f.tick], [1]);

      run.state.advance(_step);
      final frames = _drainFrames(game);
      expect(frames.single.tick, 2);
      expect(frames.single.quads.length, 1,
          reason: 'one batch per frame, not one per sprite');
    });

    test('a frame that ran several catch-up steps still produces one record', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      _size(scene.sprite, scene.addEntity(scene.sprite), 10, 10);

      // One frame worth three whole fixed steps - a stall being caught up.
      expect(run.state.advance(_step * 3), 3);
      final frames = _drainFrames(game);
      expect(frames.length, 1,
          reason: 'the renderer is a Tickable now: it presents once per frame '
              'regardless of how many simulation steps that frame afforded. '
              'Emitting three identical-latency frames for one real frame '
              'would just be three draws of the same instant.');
      expect(frames.single.tick, 3, reason: 'stamped with the tick it depicts');
    });

    test('one quad per visible, sized entity - colour carried through', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      _size(scene.sprite, scene.addEntity(scene.sprite), 10, 10, 0xFF203040);
      _size(scene.sprite, scene.addEntity(scene.sprite), 4, 4, 0x80FF0000);
      scene.addEntity(scene.sprite); // unsized - skipped
      final hidden = scene.addEntity(scene.sprite);
      _size(scene.sprite, hidden, 10, 10);
      scene.sprite.quad.visible[hidden] = 0;
      scene.addEntity(scene.invisible); // no Renderable2D at all

      run.state.advance(_step);
      final frame = _drainFrames(game).single;
      expect(frame.quads.length, 2);
      expect([for (final q in frame.quads) q.color], [0xFF203040, 0x80FF0000]);
    });

    test('a tick with nothing to draw still publishes an empty frame', () async {
      final game = await _game();
      run.state.advance(_step);
      final frame = _drainFrames(game).single;
      expect(frame.tick, 1);
      expect(frame.quads, isEmpty,
          reason: 'the consumer needs to learn the scene emptied out, not '
              'keep replaying the last non-empty frame forever');
    });

    test('every loaded scene is drawn, not just the first', () async {
      await _game();
      final state = run.state;
      final first = state.getScene<_SpriteScene>();
      _size(first.sprite, state.sceneHandle!.addEntity(first.sprite), 10, 10);

      final second = await state.loadScene(_SpriteScene());
      final secondStruct = second.get<_SpriteScene>();
      _size(secondStruct.sprite, second.addEntity(secondStruct.sprite), 10, 10);

      state.advance(_step);
      final renderer = run.state.getSystem<GameRenderer2D>();
      // This asserted the opposite until `switchScene` was deleted: the
      // renderer used to filter on the front scene's slot, so the second
      // scene simulated invisibly. "Which scene do I draw" is a question a
      // *view* answers now - and a view answers it through its camera, so
      // there is no single answer for the renderer to apply globally.
      expect(renderer.lastSpriteCount, 2,
          reason: 'both resident scenes render; a game that wants one unseen '
              'unloads it or keeps its sprites invisible');
    });

    test('the renderer reports what it wrote', () async {
      await _game();
      final scene = run.state.getScene<_SpriteScene>();
      _size(scene.sprite, scene.addEntity(scene.sprite), 10, 10);
      run.state.advance(_step);
      final renderer = run.state.getSystem<GameRenderer2D>();
      expect(renderer.lastSpriteCount, 1);
      expect(renderer.lastWriteDropped, isFalse);
    });
  });

  group('world-space quad geometry', () {
    test('an unparented entity: centred on its own offset', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final entity = scene.addEntity(scene.sprite);
      _place(scene.sprite, entity, x: 100, y: 50);
      _size(scene.sprite, entity, 40, 20);

      run.state.advance(_step);
      final quad = _drainFrames(game).single.quads.single;
      // 40x20 centred on (100,50), wound top-left -> top-right -> bottom-right
      // -> bottom-left.
      expect(quad.x, [80, 120, 120, 80]);
      expect(quad.y, [40, 40, 60, 60]);
    });

    test('scale and rotation are baked into the corners, not left to Canvas', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final entity = scene.addEntity(scene.sprite);
      _place(scene.sprite, entity, x: 10, y: 10, scaleX: 2, scaleY: 3,
          rotation: math.pi / 2);
      _size(scene.sprite, entity, 4, 2);

      run.state.advance(_step);
      final quad = _drainFrames(game).single.quads.single;
      // half extent (2,1); scale then rotate by +90 degrees maps
      // (lx,ly) -> (-3*ly, 2*lx), then translate by (10,10).
      for (final (i, local) in const [(-2.0, -1.0), (2.0, -1.0), (2.0, 1.0), (-2.0, 1.0)]
          .indexed) {
        expect(quad.x[i], closeTo(10 - 3 * local.$2, 1e-4));
        expect(quad.y[i], closeTo(10 + 2 * local.$1, 1e-4));
      }
    });

    test('a child is drawn - the query must not forbid Child', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final parent = scene.addEntity(scene.sprite);
      _place(scene.sprite, parent, x: 100, y: 100);
      _size(scene.sprite, parent, 10, 10);
      final child = scene.addEntity(scene.sprite, parent: parent);
      _place(scene.sprite, child, x: 20, y: 0);
      _size(scene.sprite, child, 2, 2, 0xFFAABBCC);

      run.state.advance(_step);
      final quads = _drainFrames(game).single.quads;
      // The regression: `With<Renderable2D>() & Without<Child>()` produced
      // one quad here, silently dropping every hierarchy-attached entity.
      expect(quads.length, 2);
      final childQuad = quads.firstWhere((q) => q.color == 0xFFAABBCC);
      expect(childQuad.x, [119, 121, 121, 119], reason: 'parent 100 + local 20');
      expect(childQuad.y, [99, 99, 101, 101]);
    });

    test('an unparented entity that merely *has* Child uses its own transform', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final entity = scene.addEntity(scene.sprite);
      _place(scene.sprite, entity, x: 7, y: 9);
      _size(scene.sprite, entity, 2, 2);
      expect(scene.sprite.parent[entity], isNull);

      run.state.advance(_step);
      final quad = _drainFrames(game).single.quads.single;
      expect(quad.x, [6, 8, 8, 6]);
      expect(quad.y, [8, 8, 10, 10]);
    });

    test('a three-level chain composes translate/scale in the right order', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();

      final grandparent = scene.addEntity(scene.sprite);
      _place(scene.sprite, grandparent, x: 100, y: 200, scaleX: 2, scaleY: 3);

      final parent = scene.addEntity(scene.sprite, parent: grandparent);
      _place(scene.sprite, parent, x: 10, y: 20, scaleX: 0.5, scaleY: 2);

      final child = scene.addEntity(scene.sprite, parent: parent);
      _place(scene.sprite, child, x: 5, y: 5);
      _size(scene.sprite, child, 4, 6, 0xFF010203);

      run.state.advance(_step);
      final quad = _drainFrames(game).single.quads
          .firstWhere((q) => q.color == 0xFF010203);

      // world = M(gp) * M(p) * M(c), each M = translate * rotate * scale:
      //   M(gp)*M(p) = [2*0.5, 0, 2*10+100; 0, 3*2, 3*20+200]
      //              = [1, 0, 120; 0, 6, 260]
      //   * M(c)     = [1, 0, 125; 0, 6, 290]
      // Half extent (2,3), so x = lx + 125 and y = 6*ly + 290. Note the
      // *child's* height is scaled by the ancestors' 3*2, not by its own 1 -
      // that product is the whole point of flattening here.
      expect(quad.x, [123, 127, 127, 123]);
      expect(quad.y, [272, 272, 308, 308]);
    });

    test('a rotated parent rotates its child about the parent origin', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final parent = scene.addEntity(scene.sprite);
      _place(scene.sprite, parent, x: 100, y: 100, rotation: math.pi / 2);
      final child = scene.addEntity(scene.sprite, parent: parent);
      _place(scene.sprite, child, x: 10, y: 0);
      _size(scene.sprite, child, 2, 2, 0xFF445566);

      run.state.advance(_step);
      final quad = _drainFrames(game).single.quads
          .firstWhere((q) => q.color == 0xFF445566);
      // The child sits 10 along the parent's local +x, which +90 degrees has
      // turned into world +y: centre (100, 110), not (110, 100).
      final centreX = quad.x.reduce((a, b) => a + b) / 4;
      final centreY = quad.y.reduce((a, b) => a + b) / 4;
      expect(centreX, closeTo(100, 1e-3));
      expect(centreY, closeTo(110, 1e-3));
    });

    test('a parent left at its default transform contributes identity', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final parent = scene.addEntity(scene.sprite);
      final child = scene.addEntity(scene.sprite, parent: parent);
      _place(scene.sprite, child, x: 3, y: 4);
      _size(scene.sprite, child, 2, 2);

      run.state.advance(_step);
      final quads = _drainFrames(game).single.quads;
      expect(quads.length, 1, reason: 'the parent is unsized');
      expect(quads.single.x, [2, 4, 4, 2]);
      expect(quads.single.y, [3, 3, 5, 5]);
    });

    test('an ancestor with no Transform2D at all is skipped, not fatal', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      // A bare grouping node: Child/Parent links, no transform of its own.
      // The walk has to step over it rather than abort, or its subtree stops
      // inheriting from everything above it.
      final top = scene.addEntity(scene.sprite);
      _place(scene.sprite, top, x: 50, y: 60);
      final group = scene.addEntity(scene.group, parent: top);
      final child = scene.addEntity(scene.sprite, parent: group);
      _place(scene.sprite, child, x: 3, y: 4);
      _size(scene.sprite, child, 2, 2, 0xFF778899);

      run.state.advance(_step);
      final quad = _drainFrames(game).single.quads
          .firstWhere((q) => q.color == 0xFF778899);
      expect(quad.x, [52, 54, 54, 52]);
      expect(quad.y, [63, 63, 65, 65]);
    });
  });

  group('buffer wiring', () {
    test('declaring the system is all it takes to get the buffer', () async {
      final game = await _game();
      expect(game.bufferCount, 0,
          reason: 'the renderer declares a handoff buffer, not a ring - frames '
              'are a value where only the newest matters, not a stream where '
              'every record does');
      final renderer = run.state.getSystem<GameRenderer2D>();
      expect(renderer.framesFor(game.view).index, 0,
          reason: 'declaring the system is the whole of the wiring - the '
              'buffer is its own declaration, not something the user repeats');
      expect(renderer.framesFor(game.view).slotBytes, renderer.spriteBatchBytes);
    });

    test('an unread frame is replaced, not queued behind', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      _size(scene.sprite, scene.addEntity(scene.sprite), 10, 10);

      run.state.advance(_step);
      run.state.advance(_step);
      expect([for (final f in _drainFrames(game)) f.tick], [2],
          reason: 'two frames produced, and the reader gets the second - the '
              'first was replaced rather than kept. A ring queued both and '
              'handed over the older one first, which is the wrong end: an '
              'old frame is the one thing a renderer never wants');

      run.state.advance(_step);
      run.state.advance(_step);
      expect([for (final f in _drainFrames(game)) f.tick], [4]);
    });
  });

  group('several sprites per entity', () {
    test('two declared sprites produce two independent records', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      scene.addEntity(scene.twoSprite);

      run.state.advance(_step);
      final quads = _drainFrames(game).single.quads;
      expect(quads.length, 2,
          reason: 'the unit of drawing is the sprite, not the entity - one '
              'entity with a body and a hat is two records, which is the whole '
              'reason Renderable2D became a MultiComponent');

      // Body: 10x10, default centred pivot, entity at the origin.
      expect(quads[0].color, 0xFF111111);
      expect(quads[0].x, [-5, 5, 5, -5]);
      expect(quads[0].y, [-5, -5, 5, 5]);

      // Hat: 4x2, pivot centred *and* offset 6 further down its own y axis,
      // so it sits above the body rather than on top of it. Different colour,
      // different size and different position from the body, all from the same
      // entity transform - proof the two sprites' rows are genuinely
      // independent storage rather than one row read twice.
      expect(quads[1].color, 0xFF222222);
      expect(quads[1].x, [-2, 2, 2, -2]);
      expect(quads[1].y, [-7, -7, -5, -5],
          reason: 'pivotY = 0.5 * 2 + 6 = 7, so the local extent runs -7 .. -5: '
              'fraction and offset are summed, not chosen between');
    });

    test('has() named parameters are the archetype row defaults - no onMounted', () async {
      await _game();
      final scene = run.state.getScene<_SpriteScene>();
      // _TwoSprite declares no onMounted at all. Every value below therefore
      // came from the storage layer stamping the declared default into a fresh
      // row, which is the property that lets a prefab be pure declaration.
      final entity = scene.addEntity(scene.twoSprite);
      final hat = scene.twoSprite.hat;
      expect(hat.width[entity], 4);
      expect(hat.height[entity], 2);
      expect(hat.color[entity], 0xFF222222);
      expect(hat.zIndex[entity], 5);
      expect(hat.visible[entity], 1);
      expect(hat.pivotFractionX[entity], 0.5);
      expect(hat.pivotOffsetY[entity], 6,
          reason: 'the RelativeOffset2D passed to has() is unpacked into four '
              'separate float64 fields at declare time - a row cannot store a '
              'value object, so this is the only shape available');
      expect(hat.alignFractionX[entity], 1);
      expect(hat.alignOffsetX[entity], 3);
      expect(hat.borderLeft[entity], 2);
      expect(hat.borderBottom[entity], 2,
          reason: 'NineSliceBorder.all(2) unpacks into all four insets');
      // And the sibling sprite is untouched by any of it.
      expect(scene.twoSprite.body.zIndex[entity], 0);
      expect(scene.twoSprite.body.width[entity], 10);
    });

    test('a runtime setter writes all four fields of a group at once', () async {
      await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final entity = scene.addEntity(scene.twoSprite);
      // The reason these exist: changing a pivot at runtime should not mean
      // remembering to poke four fields, and there is deliberately no matching
      // getter (a read returning a fresh RelativeOffset2D would allocate per
      // read on the hot path - RULES.md rule 1).
      scene.twoSprite.body.setPivot(
          entity, const RelativeOffset2D(fractionX: 0.25, offsetY: -4));
      scene.twoSprite.body.setNineSliceBorder(
          entity, const NineSliceBorder(left: 1, top: 2, right: 3, bottom: 4));
      expect(scene.twoSprite.body.pivotFractionX[entity], 0.25);
      expect(scene.twoSprite.body.pivotFractionY[entity], 0,
          reason: 'RelativeOffset2D defaults every component to zero, so an '
              'unspecified one is written as zero rather than left alone - the '
              'setter sets the whole group');
      expect(scene.twoSprite.body.pivotOffsetY[entity], -4);
      expect(scene.twoSprite.body.borderLeft[entity], 1);
      expect(scene.twoSprite.body.borderTop[entity], 2);
      expect(scene.twoSprite.body.borderRight[entity], 3);
      expect(scene.twoSprite.body.borderBottom[entity], 4);
    });
  });

  group('visibility', () {
    test('visible: false produces no record at all, not a transparent one', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      scene.addEntity(scene.halfHidden);

      run.state.advance(_step);
      final quads = _drainFrames(game).single.quads;
      expect(quads.length, 1,
          reason: 'the hidden sprite must be dropped before it becomes a '
              'record - a transparent quad would still cost a record, six '
              'vertices and a slot in the batch limit while drawing nothing');
      expect(quads.single.color, 0xFF00FF00,
          reason: 'and it is the *shown* one that survived');
    });

    test('toggling visible off at runtime removes the record next frame', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final entity = scene.addEntity(scene.halfHidden);
      run.state.advance(_step);
      expect(_drainFrames(game).single.quads.length, 1);

      // Between ticks, so the write lands in an open tick rather than in a
      // slot the next beginTick would copy over - see data_layout.dart's
      // assertion. Every other write in this file happens before the first
      // tick, where that is not yet a concern.
      final pool = run.state.scene!.pool;
      pool.beginTick();
      scene.halfHidden.shown.visible[entity] = 0;
      pool.commitTick();

      run.state.advance(_step);
      expect(_drainFrames(game).single.quads, isEmpty,
          reason: 'visibility is per-sprite row state read every tick, so '
              'hiding the last visible sprite empties the frame');
    });
  });

  group('z-ordering', () {
    test('higher zIndex draws later, whatever order the query yields', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      // Created (and therefore encountered) in the *opposite* order to the one
      // they must be drawn in, so a pass that ignored zIndex would fail here.
      _size(scene.sprite, scene.addEntity(scene.sprite), 2, 2, 0xFF000005, 5);
      _size(scene.sprite, scene.addEntity(scene.sprite), 2, 2, 0xFF000000, 0);
      _size(scene.sprite, scene.addEntity(scene.sprite), 2, 2, 0xFF000002, 2);

      run.state.advance(_step);
      final quads = _drainFrames(game).single.quads;
      expect([for (final q in quads) q.color],
          [0xFF000000, 0xFF000002, 0xFF000005],
          reason: 'painter algorithm: the record written last is rasterized '
              'last and therefore lands on top, so ascending zIndex is '
              'ascending write order');
    });

    test('equal zIndex keeps encounter order - the sort is stable', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      _size(scene.sprite, scene.addEntity(scene.sprite), 2, 2, 0xFFAA0001);
      _size(scene.sprite, scene.addEntity(scene.sprite), 2, 2, 0xFFAA0002);
      _size(scene.sprite, scene.addEntity(scene.sprite), 2, 2, 0xFFAA0003);
      _size(scene.sprite, scene.addEntity(scene.sprite), 2, 2, 0xFFAA0004);
      _size(scene.sprite, scene.addEntity(scene.sprite), 2, 2, 0xFFAA0005);

      run.state.advance(_step);
      final quads = _drainFrames(game).single.quads;
      expect([for (final q in quads) q.color],
          [0xFFAA0001, 0xFFAA0002, 0xFFAA0003, 0xFFAA0004, 0xFFAA0005],
          reason: 'query order is the tie-break, so a scene that never sets '
              'zIndex draws in exactly the order this system produced before '
              'zIndex existed - an unstable sort would silently reshuffle '
              'overlapping sprites from frame to frame');
    });

    test('ordering holds within one entity sprite list too', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      // _Stack declares its z:3 sprite *first* and its z:1 sprite second.
      scene.addEntity(scene.stack);

      run.state.advance(_step);
      final quads = _drainFrames(game).single.quads;
      expect([for (final q in quads) q.color], [_Stack.lowColor, _Stack.highColor],
          reason: 'sorting is over (entity, sprite) pairs, not over entities - '
              'two sprites on one entity sort against each other exactly as '
              'two sprites on two entities do');
    });

    test('ordering interleaves sprites of different entities', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      // Encounter order is archetype registration order, and _Sprite is
      // registered before _Stack - so this entity is seen first and has to be
      // sorted *between* the two sprites of the entity seen second.
      _size(scene.sprite, scene.addEntity(scene.sprite), 2, 2, 0xFF00FF00, 2);
      scene.addEntity(scene.stack);

      run.state.advance(_step);
      final quads = _drainFrames(game).single.quads;
      expect([for (final q in quads) q.color],
          [_Stack.lowColor, 0xFF00FF00, _Stack.highColor],
          reason: 'z is a global draw order across the whole scene, not a '
              'per-entity one - otherwise nothing could ever be drawn between '
              'two sprites of the same entity');
    });

    test('negative zIndex sorts behind the default of zero', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      _size(scene.sprite, scene.addEntity(scene.sprite), 2, 2, 0xFF000000);
      _size(scene.sprite, scene.addEntity(scene.sprite), 2, 2, 0xFFBBBBBB, -4);

      run.state.advance(_step);
      final quads = _drainFrames(game).single.quads;
      expect([for (final q in quads) q.color], [0xFFBBBBBB, 0xFF000000],
          reason: 'zIndex is a signed field, so "put this behind everything '
              'that has not been given a z" needs no rebasing of the rest of '
              'the scene');
    });
  });

  group('pivot', () {
    test('the default centred pivot puts the transform origin in the middle', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final entity = scene.addEntity(scene.sprite);
      _place(scene.sprite, entity, x: 100, y: 50);
      _size(scene.sprite, entity, 40, 20);

      run.state.advance(_step);
      final quad = _drainFrames(game).single.quads.single;
      // pivot = 0.5 * (40,20) + (0,0) = (20,10), so the local extent runs
      // -20..20 by -10..10 - identical to the pre-pivot geometry.
      expect(quad.x, [80, 120, 120, 80]);
      expect(quad.y, [40, 40, 60, 60]);
    });

    test('fraction 0,0 anchors the top-left corner on the transform origin', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final entity = scene.addEntity(scene.topLeft);
      scene.topLeft
        ..transformOffsetX[entity] = 100
        ..transformOffsetY[entity] = 50;

      run.state.advance(_step);
      final quad = _drainFrames(game).single.quads.single;
      // pivot = 0 * (40,20) + (0,0) = (0,0), so the local extent runs 0..40 by
      // 0..20: the same 40x20 sprite at the same position as the test above,
      // shifted by exactly half its own extent.
      expect(quad.x, [100, 140, 140, 100],
          reason: 'the pivot moves the quad within its own bounds, so nothing '
              'about the entity transform changed - only which point of the '
              'sprite that transform names');
      expect(quad.y, [50, 50, 70, 70]);
    });

    test('the pivot is what rotation turns about', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final entity = scene.addEntity(scene.topLeft);
      scene.topLeft
        ..transformOffsetX[entity] = 0
        ..transformOffsetY[entity] = 0
        ..transformRotation[entity] = math.pi / 2;

      run.state.advance(_step);
      final quad = _drainFrames(game).single.quads.single;
      // Local corners (0,0),(40,0),(40,20),(0,20) rotated +90 degrees:
      // (x,y) -> (-y, x). The corner sitting *on* the pivot stays put, which
      // is the whole observable difference between pivoting and translating.
      for (final (i, local) in const [(0.0, 0.0), (40.0, 0.0), (40.0, 20.0), (0.0, 20.0)]
          .indexed) {
        expect(quad.x[i], closeTo(-local.$2, 1e-4));
        expect(quad.y[i], closeTo(local.$1, 1e-4));
      }
    });
  });

  group('camera', () {
    test('no camera reproduces the pre-camera output exactly', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final entity = scene.addEntity(scene.sprite);
      _place(scene.sprite, entity, x: 100, y: 50);
      _size(scene.sprite, entity, 40, 20);
      // No _Eye entity exists in this scene, so ActiveCameraResolver returns
      // null and the renderer falls back to origin (0,0) and zoom 1. And no
      // widget ever laid this game out, so the view is zero-sized and the
      // centring term is zero too - see 'view centring' below for what a
      // real window does with the same scene.

      run.state.advance(_step);
      final quad = _drainFrames(game).single.quads.single;
      expect(quad.x, [80, 120, 120, 80],
          reason: 'subtracting a (0,0) origin and multiplying by a zoom of 1 '
              'is the identity - a game that declares no camera must get '
              'byte-for-byte what it got before cameras existed');
      expect(quad.y, [40, 40, 60, 60]);
    });

    test('a moved camera shifts every quad by the same offset', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final near = scene.addEntity(scene.sprite);
      _place(scene.sprite, near, x: 100, y: 50);
      _size(scene.sprite, near, 40, 20, 0xFF000001);
      final far = scene.addEntity(scene.sprite);
      _size(scene.sprite, far, 2, 2, 0xFF000002);

      final camera = _eye(game, scene);
      scene.eye
        ..transformOffsetX[camera] = 30
        ..transformOffsetY[camera] = 40;

      run.state.advance(_step);
      final quads = _drainFrames(game).single.quads;
      expect(quads.length, 2, reason: 'the camera itself draws nothing');
      // Both quads move by exactly -(30,40): the camera position is where
      // the view is centred, so it is subtracted, and a rigid shift is the
      // only thing a translation may do to a scene. (The centring term is
      // zero here because nothing laid this game out - it does not change
      // the shift, only where the whole scene sits.)
      expect(quads[0].x, [50, 90, 90, 50]);
      expect(quads[0].y, [0, 0, 20, 20]);
      expect(quads[1].x, [-31, -29, -29, -31]);
      expect(quads[1].y, [-41, -41, -39, -39]);
    });

    test('zoom scales position and extent together about the view origin', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final entity = scene.addEntity(scene.sprite);
      _place(scene.sprite, entity, x: 100, y: 50);
      _size(scene.sprite, entity, 40, 20);

      final camera = _eye(game, scene);
      scene.eye.zoom[camera] = 2;

      run.state.advance(_step);
      final quad = _drainFrames(game).single.quads.single;
      // (world - origin) * zoom, with the origin still at (0,0): the centre
      // moves to (200,100) and the half-extents double to (40,20). Scaling
      // only the position would slide sprites apart without magnifying them,
      // which is a different (and wrong) effect.
      expect(quad.x, [160, 240, 240, 160]);
      expect(quad.y, [80, 80, 120, 120]);
    });

    test('a camera parented into the hierarchy is followed through its world transform', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final anchor = scene.addEntity(scene.sprite);
      _place(scene.sprite, anchor, x: 200, y: 0);
      _size(scene.sprite, anchor, 2, 2);

      // The renderer reads the camera WorldTransform2D, not its local
      // Transform2D, so a camera bolted onto a moving entity needs no special
      // case anywhere in this system.
      final camera = _eye(game, scene, parent: anchor);
      scene.eye.transformOffsetX[camera] = 10;

      run.state.advance(_step);
      final quad = _drainFrames(game).single.quads.single;
      expect(quad.x, [-11, -9, -9, -11],
          reason: 'the camera resolved world x is 200 + 10, so the anchor at '
              '200 lands 10 to the left of the view origin');
      expect(quad.y, [-1, -1, 1, 1]);
    });

    test('two cameras still trip ActiveCameraResolver assert', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      scene.addEntity(scene.sprite);
      _eye(game, scene);
      _eye(game, scene);

      // Unchanged behaviour, now reached through the renderer: a camera
      // defines the single view origin, so a second one is a development-time
      // mistake that stops a debug run rather than a silent arbitrary pick.
      expect(() => run.state.advance(_step), throwsA(isA<AssertionError>()));
    });
  });

  group('view centring', () {
    test('the world origin sits in the middle of a laid-out view', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final entity = scene.addEntity(scene.sprite);
      _place(scene.sprite, entity, x: 0, y: 0);
      _size(scene.sprite, entity, 40, 20);
      // What a GameView reports from its LayoutBuilder, arriving on the same
      // wire as the rest of the input block.
      game.inputDevice!.setViewSize(800, 600);
      // The projection centres on the *view's* viewport now, not the game's
      // one global view size - that is what lets two GameViews of different
      // sizes coexist. A test has no widget to lay it out, so it says so.
      game.view.setViewport(800, 600);

      run.state.advance(_step);
      final quad = _drainFrames(game).single.quads.single;
      expect(quad.x, [380, 420, 420, 380],
          reason: 'a camera position is the centre of what you can see - '
              'Unity, Godot and Unreal all mean that by it, and a follow '
              'camera that had to add half a screen itself would be the '
              'engine leaking its own arithmetic');
      expect(quad.y, [290, 290, 310, 310]);
    });

    test('a camera puts what it is over in the middle', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final entity = scene.addEntity(scene.sprite);
      _place(scene.sprite, entity, x: 100, y: 50);
      _size(scene.sprite, entity, 40, 20);
      final camera = _eye(game, scene);
      scene.eye
        ..transformOffsetX[camera] = 100
        ..transformOffsetY[camera] = 50;
      game.inputDevice!.setViewSize(800, 600);
      // The projection centres on the *view's* viewport now, not the game's
      // one global view size - that is what lets two GameViews of different
      // sizes coexist. A test has no widget to lay it out, so it says so.
      game.view.setViewport(800, 600);

      run.state.advance(_step);
      final quad = _drainFrames(game).single.quads.single;
      expect(quad.x, [380, 420, 420, 380],
          reason: 'the camera is exactly on the sprite, so the sprite is '
              'exactly in the middle - which is the whole point of a follow '
              'camera and was not true when the camera anchored the corner');
      expect(quad.y, [290, 290, 310, 310]);
    });

    test('zoom scales about the middle, not the corner', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final entity = scene.addEntity(scene.sprite);
      _place(scene.sprite, entity, x: 0, y: 0);
      _size(scene.sprite, entity, 40, 20);
      final camera = _eye(game, scene);
      scene.pool.beginTick();
      scene.eye.zoom[camera] = 2;
      scene.pool.commitTick();
      game.inputDevice!.setViewSize(800, 600);
      // The projection centres on the *view's* viewport now, not the game's
      // one global view size - that is what lets two GameViews of different
      // sizes coexist. A test has no widget to lay it out, so it says so.
      game.view.setViewport(800, 600);

      run.state.advance(_step);
      final quad = _drainFrames(game).single.quads.single;
      expect(quad.x, [360, 440, 440, 360],
          reason: 'twice the size, still centred - zooming must not drag the '
              'scene toward a corner, which is what scaling before centring '
              'would do');
      expect(quad.y, [280, 280, 320, 320]);
    });

    test('a game nobody laid out draws plain world coordinates', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final entity = scene.addEntity(scene.sprite);
      _place(scene.sprite, entity, x: 0, y: 0);
      _size(scene.sprite, entity, 40, 20);

      run.state.advance(_step);
      final quad = _drainFrames(game).single.quads.single;
      expect(quad.x, [-20, 20, 20, -20],
          reason: 'a headless game has no view to find the middle of, and '
              'half of zero is zero - so a test that never built a widget '
              'reads world coordinates directly, which is why every other '
              'test in this file could stay as it was');
      expect(quad.y, [-10, -10, 10, 10]);
    });
  });

  group('texture', () {
    test('a textured sprite carries its address and the full-texture UVs', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final prefab = scene.texturedPair;
      scene.addEntity(prefab);

      run.state.advance(_step);
      final quads = _drainFrames(game).single.quads;
      final textured =
          quads.firstWhere((q) => q.color == _Textured.texturedColor);

      expect(textured.texture, prefab.tile.address,
          reason: 'the record carries the GlobalObject address, which is the '
              'same integer on both isolates because both ran the same '
              'describeAssets pass - it is what the main isolate resolves back '
              'into a ui.Image, and the only form a ui.Image can take here');
      expect(textured.texture, isNonNegative);
      expect(textured.u, [0, 1, 1, 0],
          reason: 'a plain sprite samples the whole texture, and the UV corner '
              'order is the position corner order: left-top, right-top, '
              'right-bottom, left-bottom');
      expect(textured.v, [0, 0, 1, 1]);
    });

    test('an untextured sprite carries the sentinel and its flat colour', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      scene.addEntity(scene.texturedPair);

      run.state.advance(_step);
      final quads = _drainFrames(game).single.quads;
      final plain = quads.firstWhere((q) => q.color == _Textured.untexturedColor);

      expect(plain.texture, DrawSpriteData2D.noTexture,
          reason: '-1 and not 0: address 0 belongs to whichever asset this '
              'process declared first, so a zero sentinel would make one real '
              'texture silently undrawable');
      expect(plain.color, _Textured.untexturedColor,
          reason: 'with no texture the colour is the fill, unchanged from '
              'before textures existed');
    });

    test('one entity mixes textured and untextured sprites in one frame', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      scene.addEntity(scene.texturedPair);

      run.state.advance(_step);
      final quads = _drainFrames(game).single.quads;
      expect(quads.length, 2);
      // zIndex 0 then 1, so the textured one is written first.
      expect([for (final q in quads) q.color],
          [_Textured.texturedColor, _Textured.untexturedColor]);
      expect(quads[0].texture, isNot(quads[1].texture),
          reason: 'the texture is per sprite, not per entity - which is the '
              'whole reason it is a Sprite field and not a Renderable2D one');
    });

    test('the producer writes the address and never reads the image', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      scene.addEntity(scene.texturedPair);

      // The trap is armed: this prefab's texture throws from `image`.
      expect(() => scene.texturedPair.tile.image, throwsStateError,
          reason: 'if this stopped throwing the rest of this test would prove '
              'nothing at all');

      // So producing a frame at all is the assertion. A `GameRenderer2D` that
      // reached for a ui.Image - to size a UV rect, to pick a shader, to do
      // anything - would blow up here instead of writing a record, which is
      // exactly what it would do on the real game isolate where the image
      // genuinely does not exist.
      expect(() => run.state.advance(_step), returnsNormally);
      final quads = _drainFrames(game).single.quads;
      expect(quads.first.texture, scene.texturedPair.tile.address);
    });

    test('a texture swapped at runtime changes the address next frame', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final entity = scene.addEntity(scene.texturedPair);
      run.state.advance(_step);
      expect(_drainFrames(game).single.quads.first.texture,
          scene.texturedPair.tile.address);

      // Between ticks, so the write lands in an open tick rather than in a slot
      // the next beginTick would copy over.
      final pool = run.state.scene!.pool;
      pool.beginTick();
      scene.texturedPair.textured.texture[entity] = null;
      pool.commitTick();

      run.state.advance(_step);
      final quads = _drainFrames(game).single.quads;
      expect(quads.first.texture, DrawSpriteData2D.noTexture,
          reason: 'the texture is ordinary per-sprite row state read every '
              'tick, so clearing it turns that sprite back into a flat colour '
              'with no re-declaration anywhere');
      expect(quads.first.color, _Textured.texturedColor,
          reason: 'and the colour it was tinting with becomes the fill');
    });

    test('the sprite batch is sized from the real stride, not a stale constant',
        () async {
      final game = await _game();
      final renderer = run.state.getSystem<GameRenderer2D>();
      expect(
        renderer.spriteBatchBytes,
        DrawData2D.batchHeaderBytes +
            game.maxSpritesPerTick * DrawSpriteData2D.strideBytes,
        reason: 'the scratch buffer and the handoff slot are both derived from '
            'the stride, so widening the record for UVs must widen them too - '
            'a hard-coded 36 here would have started silently truncating '
            'frames. The budget lives on the Game because the Game is what '
            'allocates from it; the system reads the same number back',
      );
      expect(game.framesFor(game.view).slotBytes, renderer.spriteBatchBytes);
    });
  });

  group('nine-slice', () {
    // 16x16 source, 4px inset, drawn 40x40 at the world origin with a
    // top-left pivot. Grid lines therefore land on local 0, 4, 36, 40 on both
    // axes and the UV cuts on 0, 0.25, 0.75, 1 - every one exact in binary,
    // so these are equalities rather than tolerances.
    const cuts = [0.0, 4.0, 36.0, 40.0];
    const uvCuts = [0.0, 0.25, 0.75, 1.0];

    _Frame drawPanel(_RenderGame game) {
      final scene = run.state.getScene<_SpriteScene>();
      scene.addEntity(scene.panel);
      run.state.advance(_step);
      return _drainFrames(game).single;
    }

    test('emits nine quads where a plain sprite emits one', () async {
      final game = await _game();
      expect(drawPanel(game).quads, hasLength(9),
          reason: 'four corners, four edges and a centre - the whole reason '
              'the border insets exist. A plain sprite is one quad, so this '
              'is the clearest single signal that slicing engaged at all.');
    });

    test('the 3x3 grid lands on hand-computed positions', () async {
      final game = await _game();
      final quads = drawPanel(game).quads;

      // Row-major: the generator walks rows outer, columns inner.
      for (var row = 0; row < 3; row++) {
        for (var col = 0; col < 3; col++) {
          final q = quads[row * 3 + col];
          expect(q.x, [cuts[col], cuts[col + 1], cuts[col + 1], cuts[col]],
              reason: 'cell ($row,$col) spans x ${cuts[col]}..${cuts[col + 1]}');
          expect(q.y, [cuts[row], cuts[row], cuts[row + 1], cuts[row + 1]],
              reason: 'cell ($row,$col) spans y ${cuts[row]}..${cuts[row + 1]}');
        }
      }
    });

    test('each cell samples its own sub-rect of the source image', () async {
      final game = await _game();
      final quads = drawPanel(game).quads;

      for (var row = 0; row < 3; row++) {
        for (var col = 0; col < 3; col++) {
          final q = quads[row * 3 + col];
          expect(
            q.u,
            [uvCuts[col], uvCuts[col + 1], uvCuts[col + 1], uvCuts[col]],
            reason: 'cell ($row,$col) samples u '
                '${uvCuts[col]}..${uvCuts[col + 1]} - a 4px inset on a 16px '
                'source is exactly a quarter',
          );
          expect(
            q.v,
            [uvCuts[row], uvCuts[row], uvCuts[row + 1], uvCuts[row + 1]],
            reason: 'cell ($row,$col) samples v '
                '${uvCuts[row]}..${uvCuts[row + 1]}',
          );
        }
      }
    });

    test('every cell carries the panel texture, so they stay one batch run',
        () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final quads = drawPanel(game).quads;
      final address = scene.panel.skin.address;
      for (final q in quads) {
        expect(q.texture, address,
            reason: 'all nine sample one image; if they disagreed the replay '
                'side would cut a new draw call between them and one panel '
                'would cost nine');
      }
    });

    test('growing the sprite keeps corner sizes and stretches only the middle',
        () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final entity = scene.addEntity(scene.panel);
      run.state.advance(_step);
      final small = _drainFrames(game).single.quads;

      // Same entity, twice the width. Nothing else changes.
      run.state.pool.beginTick();
      scene.panel.frame.width[entity] = 80;
      run.state.pool.commitTick();
      run.state.advance(_step);
      final large = _drainFrames(game).single.quads;

      double widthOf(_Quad q) => q.x[1] - q.x[0];

      expect(widthOf(large[0]), widthOf(small[0]),
          reason: 'the left corner column keeps its 4-unit source size at any '
              'draw width - this is the entire property nine-slicing exists '
              'for, and the one a plain stretched quad cannot give');
      expect(widthOf(large[2]), widthOf(small[2]),
          reason: 'and so does the right corner column');
      expect(widthOf(large[1]), widthOf(small[1]) + 40,
          reason: 'the centre column absorbs every unit of the extra 40 - '
              '32 wide at a 40 draw width, 72 at 80');
    });

    test('insets larger than the draw size collapse instead of inverting',
        () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      scene.addEntity(scene.unsizedPanel);
      run.state.advance(_step);
      final quads = _drainFrames(game).single.quads;

      // 4+4 of inset on a 6-unit width, scaled proportionally to 3+3, so the
      // centre column collapses to zero and is skipped in every row.
      expect(quads, hasLength(6),
          reason: 'the collapsed centre column removes one cell from each of '
              'the three rows - a zero-area quad costs a record and six '
              'vertices to rasterise nothing, so it is not emitted');

      for (final q in quads) {
        expect(q.x[1] - q.x[0], greaterThan(0),
            reason: 'no cell may invert - negative extents would render '
                'back-to-front garbage rather than a small frame');
        expect(q.y[2] - q.y[0], greaterThan(0));
      }
      expect(quads[0].x, [0.0, 3.0, 3.0, 0.0],
          reason: '4 and 4 scaled by 6/8 is 3 and 3 - proportional, so a '
              'symmetric frame stays symmetric when squeezed, where clamping '
              'in write order would have let the left inset eat all 6');
      expect(quads[1].x, [3.0, 6.0, 6.0, 3.0],
          reason: 'and the two surviving columns meet exactly, leaving no gap');
    });

    test('a collapsed destination does not re-slice the source', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      scene.addEntity(scene.unsizedPanel);
      run.state.advance(_step);
      final quads = _drainFrames(game).single.quads;

      expect(quads[0].u, [0.0, 0.25, 0.25, 0.0],
          reason: 'the destination squeezed 4 units into 3, but the image is '
              'still cut at its own 4/16. Compressing the UVs to match would '
              'shrink what the corner samples and blur it - the opposite of '
              'what nine-slicing is for');
    });

    test('a bordered sprite with no texture is a plain quad', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      scene.addEntity(scene.borderedUntextured);
      run.state.advance(_step);
      final quads = _drainFrames(game).single.quads;

      expect(quads, hasLength(1),
          reason: 'slicing subdivides image space; with no image the nine '
              'flat-coloured cells would be pixel-identical to the one quad '
              'they tile, so the insets are ignored rather than honoured '
              'pointlessly');
      expect(quads.single.texture, DrawSpriteData2D.noTexture);
    });

    test('the grid rotates with the entity instead of shearing apart', () async {
      final game = await _game();
      final scene = run.state.getScene<_SpriteScene>();
      final entity = scene.addEntity(scene.panel);
      scene.panel.transformRotation[entity] = math.pi / 2;
      run.state.advance(_step);
      final quads = _drainFrames(game).single.quads;

      // A quarter turn sends local (x, y) to world (-y, x). Checking the far
      // corner of the outermost cell pins that the whole grid went through
      // the same transform the single-quad path uses, rather than each cell
      // being rotated about its own origin.
      expect(quads[8].x[2], closeTo(-40, 1e-9),
          reason: 'the bottom-right cell reaches local (40,40), which a '
              'quarter turn puts at world (-40, 40)');
      expect(quads[8].y[2], closeTo(40, 1e-9));

      // Adjacent cells still share an edge - what a sheared grid would fail.
      expect(quads[0].x[1], closeTo(quads[1].x[0], 1e-9),
          reason: 'cell (0,0) right edge and cell (0,1) left edge are the '
              'same grid line, so they must land on the same world point');
      expect(quads[0].y[1], closeTo(quads[1].y[0], 1e-9));
    });

    test('a nine-sliced sprite spends nine of the record budget, not one',
        () async {
      await _game();
      final renderer = run.state.getSystem<GameRenderer2D>();
      final scene = run.state.getScene<_SpriteScene>();
      scene.addEntity(scene.panel);
      run.state.advance(_step);
      expect(renderer.lastRecordCount, 9,
          reason: 'the budget is counted in records, not sprites - counting '
              'sprites would let nine times maxSpritesPerTick through and '
              'overrun the scratch buffer, which is sized from that number '
              'times the record stride');
    });
  });
}
