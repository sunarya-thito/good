import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

// DrawCanvas2D, the main-isolate replay side: does one frame become the right
// drawVertices calls with the geometry the producer wrote, does texture
// batching preserve the z order the producer sorted into, and does the replay
// path stay inside RULES.md rule 3 (no save/restore/rotate/translate/
// drawImage). The last is enforced by a spy Canvas that traps every call, not
// by a promise in a doc comment.

/// Traps every `Canvas` call. `noSuchMethod` catches the ~50 members this
/// class does not implement, which is what makes "the log contains only
/// drawVertices" a real assertion about the whole surface rather than about
/// the handful of methods someone remembered to override.
class _SpyCanvas implements Canvas {
  final List<String> calls = <String>[];

  /// Every `drawVertices` in the order it was issued - which is the whole
  /// point now that one frame can produce several.
  final List<Vertices> allVertices = <Vertices>[];
  final List<BlendMode> allBlendModes = <BlendMode>[];
  final List<Paint> allPaints = <Paint>[];

  Vertices? get vertices => allVertices.isEmpty ? null : allVertices.last;
  BlendMode? get blendMode => allBlendModes.isEmpty ? null : allBlendModes.last;
  Paint? get paint => allPaints.isEmpty ? null : allPaints.last;

  @override
  void drawVertices(Vertices vertices, BlendMode blendMode, Paint paint) {
    calls.add('drawVertices');
    allVertices.add(vertices);
    allBlendModes.add(blendMode);
    allPaints.add(paint);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    // Symbol("save") -> save
    calls.add(name.substring(name.indexOf('"') + 1, name.lastIndexOf('"')));
    return null;
  }
}

const List<String> _forbidden = <String>[
  'save',
  'saveLayer',
  'restore',
  'rotate',
  'translate',
  'scale',
  'transform',
  'drawImage',
  'drawImageRect',
  'drawImageNine',
  'drawAtlas',
];

/// Asserts the whole of RULES.md rule 3 against a spy that just replayed: not
/// one of the forbidden calls appears, whatever else did.
void _expectNoForbiddenCalls(_SpyCanvas spy) {
  for (final call in _forbidden) {
    expect(spy.calls, isNot(contains(call)),
        reason: 'RULES.md rule 3: texturing goes through an ImageShader on the '
            'paint, so nothing in this pipeline may reach for $call');
  }
}

/// The whole-texture UVs, in the corner order the positions use.
const List<double> _fullUvs = <double>[0, 0, 1, 0, 1, 1, 0, 1];

/// One quad's worth of what the game isolate would have written.
class _Q {
  const _Q(
    this.corners,
    this.color, {
    this.texture = DrawSpriteData2D.noTexture,
    this.uvs = _fullUvs,
  });

  final List<double> corners;
  final int color;
  final int texture;
  final List<double> uvs;
}

/// Builds the batch payload the game isolate would have written.
Uint8List _spriteBatch(int tick, List<_Q> quads) {
  final bytes = Uint8List(
    DrawData2D.batchHeaderBytes + quads.length * DrawSpriteData2D.strideBytes,
  );
  final view = ByteData.sublistView(bytes);
  DrawData2D.writeBatchTick(view, tick);
  var offset = DrawData2D.batchHeaderBytes;
  for (final quad in quads) {
    final c = quad.corners;
    final uv = quad.uvs;
    offset = DrawSpriteData2D.writeQuad(
      view,
      offset,
      c[0], c[1],
      c[2], c[3],
      c[4], c[5],
      c[6], c[7],
      quad.color,
      textureAddress: quad.texture,
      u0: uv[0], v0: uv[1],
      u1: uv[2], v1: uv[3],
      u2: uv[4], v2: uv[5],
      u3: uv[6], v3: uv[7],
    );
  }
  return bytes;
}

RingBufferRecord _record(int tick, List<_Q> quads) =>
    RingBufferRecord(DrawSpriteData2D.spriteRecordType, _spriteBatch(tick, quads));

const List<double> _unitQuad = [0, 0, 10, 0, 10, 10, 0, 10];
const List<double> _otherQuad = [20, 20, 30, 20, 30, 30, 20, 30];

/// A 2x1 PNG whose left pixel is opaque red and right pixel opaque blue - the
/// smallest image that can tell a correct UV mapping from a mirrored one, and
/// the same fixture `texture_test.dart` decodes.
final Uint8List _png2x1 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR42mP4z8AAQv8BD/kD'
  '/Zh51wAAAAAASUVORK5CYII=',
);

/// Declares (and therefore addresses) some textures the way a scene does -
/// `initializeScene` is the one supported way to run a `describeAssets` pass
/// outside a full `Game` boot.
class _TextureScene extends SceneStruct {
  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late final Scene handle;

  Entity addEntity<T extends EntityStruct<T>>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _TextureScene(this.keys) : super();

  final List<GameAsset<Texture>> keys;
  final List<Texture> textures = <Texture>[];

  @override
  void describeAssets(AssetDescriptor descriptor) {
    for (final key in keys) {
      textures.add(descriptor.has(key));
    }
  }
}

/// [count] declared *and decoded* textures - real `ui.Image`s, so the shader
/// this suite builds is the shader a real frame would build.
Future<List<Texture>> _textures(int count) async {
  final keys = <GameAsset<Texture>>[
    for (var i = 0; i < count; i++)
      TextureAsset(MemoryImageSource(_png2x1, name: 'tex$i')),
  ];
  final scene = _TextureScene(keys)..initializeScene(MemoryPool(pageSize: 4096), assets: assets);
  scene.handle = SceneRegistry.register(scene);
  addTearDown(scene.pool.dispose);
  for (final key in keys) {
    await assets.load(key);
  }
  return scene.textures;
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

  group('spy sanity', () {
    test('the spy actually traps the calls this suite claims never happen', () {
      // Without this, "calls contains only drawVertices" would pass just as
      // happily against a spy whose noSuchMethod silently swallowed things.
      final spy = _SpyCanvas();
      spy.save();
      spy.restore();
      spy.translate(1, 2);
      spy.rotate(0.5);
      expect(spy.calls, ['save', 'restore', 'translate', 'rotate']);
    });
  });

  group('ingest', () {
    test('a frame becomes six vertices per quad and reports the change', () {
      final canvas = DrawCanvas2D(assets: assets);
      expect(canvas.hasFrame, isFalse);
      expect(canvas.frameTick, -1);

      expect(canvas.ingest([_record(7, [const _Q(_unitQuad, 0xFF00FF00)])]), isTrue);
      expect(canvas.frameTick, 7);
      expect(canvas.hasFrame, isTrue);
      expect(canvas.vertexCount, 6);
      // Two triangles, fan-split 0-1-2 / 0-2-3.
      expect(canvas.positions, [0, 0, 10, 0, 10, 10, 0, 0, 10, 10, 0, 10]);
      // Int32List is signed - same 32 bits, negative when read back.
      expect(canvas.colors.map((c) => c.toUnsigned(32)), List.filled(6, 0xFF00FF00));
    });

    test('re-ingesting the same or an older frame changes nothing', () {
      final canvas = DrawCanvas2D(assets: assets);
      canvas.ingest([_record(7, [const _Q(_unitQuad, 0xFF00FF00)])]);
      expect(canvas.ingest([_record(7, [const _Q(_otherQuad, 0xFFFF0000)])]), isFalse);
      expect(canvas.ingest([_record(3, [const _Q(_otherQuad, 0xFFFF0000)])]), isFalse);
      expect(canvas.frameTick, 7);
      expect(canvas.colors.first.toUnsigned(32), 0xFF00FF00);
    });

    test('a drain holding several ticks paints the newest, not the oldest', () {
      final canvas = DrawCanvas2D(assets: assets);
      // Exactly what a main isolate that missed two ticks drains. Replaying
      // tick 4 and *then* 5 and 6 would be pure added latency; replaying only
      // 4 would be worse.
      expect(
        canvas.ingest([
          _record(4, [const _Q(_unitQuad, 0xFF111111)]),
          _record(5, [const _Q(_unitQuad, 0xFF222222)]),
          _record(6, [const _Q(_otherQuad, 0xFF333333)]),
        ]),
        isTrue,
      );
      expect(canvas.frameTick, 6);
      expect(canvas.vertexCount, 6);
      expect(canvas.colors.first.toUnsigned(32), 0xFF333333);
      expect(canvas.positions.first, 20);
    });

    test('an empty drain, and one holding only unknown record types, are no-ops', () {
      final canvas = DrawCanvas2D(assets: assets);
      expect(canvas.ingest(<RingBufferRecord>[]), isFalse);
      expect(
        canvas.ingest([RingBufferRecord(999, _spriteBatch(9, const []))]),
        isFalse,
        reason: 'an unregistered type is skipped, not fatal - an older main '
            'isolate keeps painting what it does understand',
      );
      expect(canvas.hasFrame, isFalse);
    });

    test('an empty frame clears the geometry rather than freezing it', () {
      final canvas = DrawCanvas2D(assets: assets);
      canvas.ingest([_record(1, [const _Q(_unitQuad, 0xFF00FF00)])]);
      expect(canvas.vertexCount, 6);
      expect(canvas.ingest([_record(2, const [])]), isTrue);
      expect(canvas.vertexCount, 0);
      expect(canvas.runCount, 0,
          reason: 'no quads means no runs, so replay issues no draw call at '
              'all rather than one empty one');
    });

    test('many quads batch into one geometry buffer', () {
      final canvas = DrawCanvas2D(assets: assets);
      canvas.ingest([
        _record(1, [for (var i = 0; i < 500; i++) _Q(_unitQuad, 0xFF000000 + i)]),
      ]);
      expect(canvas.vertexCount, 3000);
      expect(canvas.positions.length, 6000);
      expect(canvas.colors.last.toUnsigned(32), 0xFF000000 + 499);
    });

    test('UVs survive the round trip, one pair per vertex in the fan split', () {
      final canvas = DrawCanvas2D(assets: assets);
      canvas.ingest([_record(1, [const _Q(_unitQuad, 0xFFFFFFFF, texture: 3)])]);
      expect(canvas.texCoords.length, 12,
          reason: 'a u,v per vertex, matching positions one for one - Vertices'
              '.raw rejects any other pairing');
      // The same 0-1-2 / 0-2-3 split the positions use, so vertex n's UV
      // belongs to vertex n's corner. A split that disagreed would shear the
      // texture across the diagonal.
      expect(canvas.texCoords, [0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1]);
    });
  });

  group('replay', () {
    test('one drawVertices for the whole frame, and nothing else at all', () {
      final canvas = DrawCanvas2D(assets: assets);
      canvas.ingest([
        _record(1, [
          const _Q(_unitQuad, 0xFF00FF00),
          const _Q(_otherQuad, 0xFFFF0000),
        ]),
      ]);

      final spy = _SpyCanvas();
      canvas.replay(spy);

      expect(spy.calls, ['drawVertices'],
          reason: 'two untextured quads share the one untextured run, so they '
              'are still one call - and no matrix-stack call anywhere');
      _expectNoForbiddenCalls(spy);
      expect(spy.vertices, isNotNull);
      // BlendMode.dst keeps the destination - the per-vertex colours - rather
      // than the paint's own colour.
      expect(spy.blendMode, BlendMode.dst);
      expect(spy.paint!.shader, isNull,
          reason: 'an untextured run must not carry a shader - the flat-colour '
              'path is unchanged by textures existing');
      expect(canvas.vertexCount, 12);
    });

    test('replaying with no frame draws nothing rather than an empty mesh', () {
      final spy = _SpyCanvas();
      DrawCanvas2D(assets: assets).replay(spy);
      expect(spy.calls, isEmpty);
    });

    test('repeated replays of one frame reuse the built Vertices', () {
      final canvas = DrawCanvas2D(assets: assets);
      canvas.ingest([_record(1, [const _Q(_unitQuad, 0xFF00FF00)])]);

      final first = _SpyCanvas();
      canvas.replay(first);
      final second = _SpyCanvas();
      canvas.replay(second);
      // Rebuilding per paint would allocate a native mesh at compositor rate
      // for geometry that provably has not moved.
      expect(second.vertices, same(first.vertices));

      canvas.ingest([_record(2, [const _Q(_otherQuad, 0xFF00FF00)])]);
      final third = _SpyCanvas();
      canvas.replay(third);
      expect(third.vertices, isNot(same(first.vertices)));
      canvas.dispose();
    });

    test('replays onto a real Canvas and produces a picture', () {
      final canvas = DrawCanvas2D(assets: assets);
      canvas.ingest([_record(1, [const _Q(_unitQuad, 0xFF00FF00)])]);
      final recorder = PictureRecorder();
      canvas.replay(Canvas(recorder));
      final picture = recorder.endRecording();
      addTearDown(picture.dispose);
      expect(picture, isNotNull);
      canvas.dispose();
    });
  });

  group('texture batching', () {
    test('many sprites sharing one texture are still a single draw call', () async {
      final tex = (await _textures(1)).single;
      final canvas = DrawCanvas2D(assets: assets);
      canvas.ingest([
        _record(1, [
          for (var i = 0; i < 20; i++)
            _Q(_unitQuad, 0xFFFFFFFF, texture: tex.address),
        ]),
      ]);
      expect(canvas.runCount, 1);

      final spy = _SpyCanvas();
      canvas.replay(spy);
      expect(spy.calls, ['drawVertices'],
          reason: 'batching by texture is the whole point: 20 sprites off one '
              'atlas must cost one call, not 20');
      expect(spy.allBlendModes, [BlendMode.modulate],
          reason: 'modulate multiplies the sampled texel by the per-vertex '
              'tint, so the default opaque white draws the texture as decoded');
      expect(spy.paint!.shader, isA<ImageShader>());
      _expectNoForbiddenCalls(spy);
      canvas.dispose();
    });

    test('two textures are two calls, one per contiguous run', () async {
      final textures = await _textures(2);
      final canvas = DrawCanvas2D(assets: assets);
      canvas.ingest([
        _record(1, [
          _Q(_unitQuad, 0xFFFFFFFF, texture: textures[0].address),
          _Q(_unitQuad, 0xFFFFFFFF, texture: textures[0].address),
          _Q(_otherQuad, 0xFFFFFFFF, texture: textures[1].address),
        ]),
      ]);
      expect(canvas.runCount, 2);
      expect(
        [for (var r = 0; r < canvas.runCount; r++) canvas.runTextureAt(r)],
        [textures[0].address, textures[1].address],
      );

      final spy = _SpyCanvas();
      canvas.replay(spy);
      expect(spy.calls, ['drawVertices', 'drawVertices']);
      expect(spy.allPaints[0], isNot(same(spy.allPaints[1])),
          reason: 'two textures means two shaders, so the paints cannot be the '
              'same object - if they were, one texture would be drawn twice');
      _expectNoForbiddenCalls(spy);
      canvas.dispose();
    });

    test('a textured and an untextured sprite are two calls with two blends', () async {
      final tex = (await _textures(1)).single;
      final canvas = DrawCanvas2D(assets: assets);
      canvas.ingest([
        _record(1, [
          _Q(_unitQuad, 0xFFFFFFFF, texture: tex.address),
          const _Q(_otherQuad, 0xFF00FF00),
        ]),
      ]);
      expect(canvas.runCount, 2);

      final spy = _SpyCanvas();
      canvas.replay(spy);
      expect(spy.calls, ['drawVertices', 'drawVertices']);
      expect(spy.allBlendModes, [BlendMode.modulate, BlendMode.dst],
          reason: 'the untextured run keeps the flat-colour blend it always '
              'had, so mixing the two in one scene changes neither');
      expect(spy.allPaints[0].shader, isA<ImageShader>());
      expect(spy.allPaints[1].shader, isNull);
      _expectNoForbiddenCalls(spy);
      canvas.dispose();
    });

    test('z order survives batching: A-B-A is three calls in that order', () async {
      final textures = await _textures(2);
      final a = textures[0].address;
      final b = textures[1].address;
      final canvas = DrawCanvas2D(assets: assets);
      // The producer already z-sorted these, so this *is* back-to-front order.
      canvas.ingest([
        _record(1, [
          _Q(_unitQuad, 0xFFFFFFFF, texture: a),
          _Q(_otherQuad, 0xFFFFFFFF, texture: b),
          _Q(_unitQuad, 0xFFFFFFFF, texture: a),
        ]),
      ]);

      expect(
        [for (var r = 0; r < canvas.runCount; r++) canvas.runTextureAt(r)],
        [a, b, a],
        reason: 'grouping the frame by texture would make this two runs (A+A, '
            'then B) and silently move the second A behind B - the painter '
            'algorithm makes draw order the depth, so a reorder here is a '
            'rendering bug, not an optimisation. Three calls is the price.',
      );

      final spy = _SpyCanvas();
      canvas.replay(spy);
      expect(spy.calls, ['drawVertices', 'drawVertices', 'drawVertices']);
      expect(spy.allPaints[0], same(spy.allPaints[2]),
          reason: 'the same texture in two runs still shares one cached '
              'shader - the run split costs a draw call, never a second upload');
      expect(spy.allPaints[1], isNot(same(spy.allPaints[0])));
      _expectNoForbiddenCalls(spy);
      canvas.dispose();
    });

    test('alternating textures degrade to one call per quad, as documented', () async {
      final textures = await _textures(2);
      final canvas = DrawCanvas2D(assets: assets);
      canvas.ingest([
        _record(1, [
          for (var i = 0; i < 6; i++)
            _Q(_unitQuad, 0xFFFFFFFF, texture: textures[i.isEven ? 0 : 1].address),
        ]),
      ]);
      expect(canvas.runCount, 6,
          reason: 'the pathological case, stated as a test rather than left to '
              'be discovered: interleaved textures cannot be batched without '
              'reordering, so the fix belongs upstream (an atlas, or a z '
              'assignment that keeps same-texture sprites adjacent)');
      canvas.dispose();
    });

    test('one shader per texture, built once and reused across frames', () async {
      final tex = (await _textures(1)).single;
      final canvas = DrawCanvas2D(assets: assets);

      canvas.ingest([_record(1, [_Q(_unitQuad, 0xFFFFFFFF, texture: tex.address)])]);
      final first = _SpyCanvas();
      canvas.replay(first);

      canvas.ingest([_record(2, [_Q(_otherQuad, 0xFFFFFFFF, texture: tex.address)])]);
      final second = _SpyCanvas();
      canvas.replay(second);

      expect(second.paint, same(first.paint),
          reason: 'an ImageShader binds engine-side state; building one per '
              'frame at compositor rate is exactly the hot-path allocation '
              'RULES.md rule 1 exists to prevent');
      expect(second.vertices, isNot(same(first.vertices)),
          reason: 'the geometry did move, so the mesh is rebuilt even though '
              'the shader is not');
      canvas.dispose();
    });

    test('runs split by texture even when the geometry is one long stretch', () async {
      final textures = await _textures(3);
      final canvas = DrawCanvas2D(assets: assets);
      canvas.ingest([
        _record(1, [
          for (final t in textures) _Q(_unitQuad, 0xFFFFFFFF, texture: t.address),
          const _Q(_unitQuad, 0xFF0000FF),
        ]),
      ]);
      expect(canvas.runCount, 4);
      expect(canvas.vertexCount, 24,
          reason: 'the runs are slices of one shared vertex buffer, not four '
              'buffers - splitting the draw must not split the storage');
      canvas.dispose();
    });
  });

  group('texture resolution', () {
    test('an address resolves to the declared Texture and its decoded image', () async {
      final tex = (await _textures(1)).single;
      expect(assets.resolve<Texture>(tex.address), same(tex),
          reason: 'this is the exact lookup replay makes: the record carries '
              'the integer, the registry turns it back into the image, and the '
              'game isolate never has to hold a ui.Image at all');
      expect(tex.image.width, 2);
    });

    test('an address that resolves to nothing fails loudly, not silently', () {
      final canvas = DrawCanvas2D(assets: assets);
      // 4242 was never registered on this isolate - a stale record, or an
      // asset unloaded out from under a frame still in flight.
      canvas.ingest([_record(1, [const _Q(_unitQuad, 0xFFFFFFFF, texture: 4242)])]);
      expect(
        () => canvas.replay(_SpyCanvas()),
        throwsA(isA<StateError>()),
        reason: 'the alternative is sampling nothing and painting garbage, '
            'which looks like an art bug and costs a day to trace back here',
      );
      canvas.dispose();
    });

    test('a declared but never decoded texture fails through requireLoaded', () async {
      // Declared, so the address resolves - but never loaded, which is the
      // permanent state of every Texture on the game isolate and the state of
      // a main-isolate one before loadScene finishes.
      final key = TextureAsset(MemoryImageSource(_png2x1, name: 'undecoded.png'));
      final scene = _TextureScene(<GameAsset<Texture>>[key])..initializeScene(MemoryPool(pageSize: 4096), assets: assets);
  scene.handle = SceneRegistry.register(scene);
      addTearDown(scene.pool.dispose);
      final canvas = DrawCanvas2D(assets: assets);
      canvas.ingest([
        _record(1, [_Q(_unitQuad, 0xFFFFFFFF, texture: scene.textures.single.address)]),
      ]);
      expect(
        () => canvas.replay(_SpyCanvas()),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('undecoded.png'), contains('never loaded')),
        )),
        reason: 'requireLoaded already names the asset - replay must let that '
            'through rather than substituting a blank shader',
      );
      canvas.dispose();
    });

    test('the sentinel is never a real address, so 0 stays drawable', () async {
      final tex = (await _textures(1)).single;
      expect(tex.address, 0,
          reason: 'GlobalObjectRegistry appends from zero, so the first asset '
              'a process declares owns address 0 - which is why the untextured '
              'sentinel has to be -1 and the field has to be signed');
      expect(DrawSpriteData2D.noTexture, -1);
      expect(DrawSpriteData2D.noTexture, isNot(tex.address));

      final canvas = DrawCanvas2D(assets: assets);
      canvas.ingest([_record(1, [_Q(_unitQuad, 0xFFFFFFFF, texture: tex.address)])]);
      final spy = _SpyCanvas();
      canvas.replay(spy);
      expect(spy.paint!.shader, isA<ImageShader>(),
          reason: 'address 0 is a texture like any other - a sentinel of 0 '
              'would have made the first-declared texture invisible');
      canvas.dispose();
    });
  });

  group('rasterized output', () {
    test('a textured quad really samples the image, right way round', () async {
      final tex = (await _textures(1)).single;
      final canvas = DrawCanvas2D(assets: assets);
      // An 8x4 quad over a 2x1 texture: the left half must come out red and
      // the right half blue. A flipped u, or an ImageShader matrix scaling the
      // wrong way, changes this picture and nothing else in the suite would
      // notice.
      canvas.ingest([
        _record(1, [
          _Q(const [0, 0, 8, 0, 8, 4, 0, 4], 0xFFFFFFFF, texture: tex.address),
        ]),
      ]);

      final recorder = PictureRecorder();
      canvas.replay(Canvas(recorder));
      final picture = recorder.endRecording();
      addTearDown(picture.dispose);
      final image = await picture.toImage(8, 4);
      addTearDown(image.dispose);
      final pixels = (await image.toByteData(format: ImageByteFormat.rawRgba))!;

      int at(int x, int y) => pixels.getUint32((y * 8 + x) * 4);
      expect(at(1, 2), 0xFF0000FF,
          reason: 'RGBA: the left half samples the texture left pixel, which '
              'is opaque red - proof the 0..1 UVs address the whole image '
              'rather than one texel, and that nothing mirrored them');
      expect(at(6, 2), 0x0000FFFF,
          reason: 'and the right half samples the blue one');
      canvas.dispose();
    });

    test('a partial UV rectangle samples only that part of the texture', () async {
      final tex = (await _textures(1)).single;
      final canvas = DrawCanvas2D(assets: assets);
      // u runs 0..0.5, i.e. the texture's left pixel only. Nothing in the
      // engine writes UVs other than the full square yet - this is the
      // property the record format has to already have for the nine-slice and
      // atlas work to be additive rather than a second wire format.
      canvas.ingest([
        _record(1, [
          _Q(
            const [0, 0, 8, 0, 8, 4, 0, 4],
            0xFFFFFFFF,
            texture: tex.address,
            uvs: const [0, 0, 0.5, 0, 0.5, 1, 0, 1],
          ),
        ]),
      ]);
      final recorder = PictureRecorder();
      canvas.replay(Canvas(recorder));
      final picture = recorder.endRecording();
      addTearDown(picture.dispose);
      final image = await picture.toImage(8, 4);
      addTearDown(image.dispose);
      final pixels = (await image.toByteData(format: ImageByteFormat.rawRgba))!;

      int at(int x, int y) => pixels.getUint32((y * 8 + x) * 4);
      expect(at(1, 2), 0xFF0000FF);
      expect(at(6, 2), 0xFF0000FF,
          reason: 'the whole quad is red because the whole quad now maps into '
              'the texture left pixel - the UVs are per corner and honoured, '
              'not a fixed full-image mapping baked into the shader');
      canvas.dispose();
    });

    test('the colour tints the texture rather than replacing it', () async {
      final tex = (await _textures(1)).single;
      final canvas = DrawCanvas2D(assets: assets);
      // Half-brightness white: modulate multiplies, so red 255 becomes 128.
      canvas.ingest([
        _record(1, [
          _Q(const [0, 0, 8, 0, 8, 4, 0, 4], 0xFF808080, texture: tex.address),
        ]),
      ]);
      final recorder = PictureRecorder();
      canvas.replay(Canvas(recorder));
      final picture = recorder.endRecording();
      addTearDown(picture.dispose);
      final image = await picture.toImage(8, 4);
      addTearDown(image.dispose);
      final pixels = (await image.toByteData(format: ImageByteFormat.rawRgba))!;

      final red = pixels.getUint8(((2 * 8) + 1) * 4);
      expect(red, closeTo(128, 2),
          reason: 'Sprite.color is a tint on a textured sprite and a fill on an '
              'untextured one - the same field, which is only possible because '
              'modulate against opaque white is the identity');
      canvas.dispose();
    });
  });

  group('disposal', () {
    test('dispose releases the shaders as well as the meshes', () async {
      final tex = (await _textures(1)).single;
      final canvas = DrawCanvas2D(assets: assets);
      canvas.ingest([_record(1, [_Q(_unitQuad, 0xFFFFFFFF, texture: tex.address)])]);
      final spy = _SpyCanvas();
      canvas.replay(spy);
      final shader = spy.paint!.shader!;
      expect(shader.debugDisposed, isFalse);

      canvas.dispose();
      expect(shader.debugDisposed, isTrue,
          reason: 'an ImageShader holds engine-side state the Dart GC does not '
              'account for, exactly like the ui.Image behind it - a cache that '
              'never released would leak one per texture per canvas');
    });

    test('dispose is safe with no frame ever ingested', () {
      expect(DrawCanvas2D(assets: assets).dispose, returnsNormally);
    });
  });

  group('registry', () {
    test('the standard registry knows sprites and nothing else', () {
      expect(DrawRegistry2D.standard[DrawSpriteData2D.spriteRecordType],
          isA<DrawSpriteData2D>());
      expect(DrawRegistry2D.standard[42], isNull);
    });

    test('registering one record type twice is an error, not a silent replace', () {
      final registry = DrawRegistry2D()..register(const DrawSpriteData2D());
      expect(() => registry.register(const DrawSpriteData2D()), throwsStateError);
    });

    test('itemCount is derived from the payload length, so no count field', () {
      const sprite = DrawSpriteData2D();
      expect(sprite.itemCount(DrawData2D.batchHeaderBytes), 0);
      expect(
        sprite.itemCount(DrawData2D.batchHeaderBytes + 3 * DrawSpriteData2D.strideBytes),
        3,
      );
    });

    test('writer and reader agree on where the texture address sits', () {
      final batch = ByteData(
        DrawData2D.batchHeaderBytes + 2 * DrawSpriteData2D.strideBytes,
      );
      var offset = DrawData2D.batchHeaderBytes;
      offset = DrawSpriteData2D.writeQuad(
          batch, offset, 0, 0, 1, 0, 1, 1, 0, 1, 0xFFFFFFFF, textureAddress: 7);
      DrawSpriteData2D.writeQuad(batch, offset, 0, 0, 1, 0, 1, 1, 0, 1, 0xFFFFFFFF);
      expect(DrawSpriteData2D.textureAddressAt(batch, 0), 7);
      expect(DrawSpriteData2D.textureAddressAt(batch, 1), DrawSpriteData2D.noTexture,
          reason: 'the writer default and the sentinel are the same value - if '
              'they ever drift, an untextured sprite starts resolving some '
              'arbitrary asset');
    });
  });

  group('VertexBatch2D', () {
    test('grows past its initial capacity without losing what it held', () {
      final batch = VertexBatch2D(initialQuadCapacity: 1);
      for (var i = 0; i < 10; i++) {
        batch.addQuad(i * 1.0, 0, i + 1.0, 0, i + 1.0, 1, i * 1.0, 1, 0xFF000000 + i);
      }
      expect(batch.vertexCount, 60);
      expect(batch.positions.first, 0);
      expect(batch.colors.first.toUnsigned(32), 0xFF000000);
      expect(batch.colors.last.toUnsigned(32), 0xFF000009);
    });

    test('the run table grows with the quads, one run per texture change', () {
      // initialQuadCapacity 1, so every quad after the first goes through the
      // grow path - and every quad opens its own run, which is the case that
      // would overflow a run table that grew on a different schedule.
      final batch = VertexBatch2D(initialQuadCapacity: 1);
      for (var i = 0; i < 10; i++) {
        batch.addQuad(0, 0, 1, 0, 1, 1, 0, 1, 0xFFFFFFFF, textureAddress: i);
      }
      expect(batch.runCount, 10);
      expect([for (var r = 0; r < 10; r++) batch.runTextureAt(r)],
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
      expect([for (var r = 0; r < 10; r++) batch.runVertexStart(r)],
          [0, 6, 12, 18, 24, 30, 36, 42, 48, 54]);
      expect(batch.runVertexEnd(9), 60);
    });

    test('consecutive quads on one texture merge into a single run', () {
      final batch = VertexBatch2D();
      batch.addQuad(0, 0, 1, 0, 1, 1, 0, 1, 0xFFFFFFFF, textureAddress: 2);
      batch.addQuad(0, 0, 1, 0, 1, 1, 0, 1, 0xFFFFFFFF, textureAddress: 2);
      batch.addQuad(0, 0, 1, 0, 1, 1, 0, 1, 0xFFFFFFFF, textureAddress: 5);
      batch.addQuad(0, 0, 1, 0, 1, 1, 0, 1, 0xFFFFFFFF, textureAddress: 2);
      expect(batch.runCount, 3,
          reason: 'adjacency, not identity, is what merges: the fourth quad is '
              'texture 2 again but cannot join the first run without jumping '
              'the third quad in draw order');
      expect([for (var r = 0; r < 3; r++) batch.runVertexEnd(r)], [12, 18, 24]);
    });

    test('untextured quads are a run like any other', () {
      final batch = VertexBatch2D();
      batch.addQuad(0, 0, 1, 0, 1, 1, 0, 1, 0xFFFFFFFF);
      batch.addQuad(0, 0, 1, 0, 1, 1, 0, 1, 0xFFFFFFFF);
      expect(batch.runCount, 1);
      expect(batch.runTextureAt(0), DrawSpriteData2D.noTexture);
    });

    test('reset empties it without reallocating what it already held', () {
      final batch = VertexBatch2D();
      batch.addQuad(0, 0, 1, 0, 1, 1, 0, 1, 0xFFFFFFFF);
      batch.reset();
      expect(batch.vertexCount, 0);
      expect(batch.positions, isEmpty);
      expect(batch.colors, isEmpty);
      expect(batch.texCoords, isEmpty);
      expect(batch.runCount, 0,
          reason: 'a stale run table would make the next frame draw slices of '
              'a buffer it no longer owns');
    });
  });
}
