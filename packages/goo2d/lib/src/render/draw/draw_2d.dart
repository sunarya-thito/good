/// The draw-command buffer's wire format and its main-isolate replay side.
///
/// Per the architecture guide's "four lanes across the boundary": the game
/// isolate's `GameRenderer2D` is the only producer of draw records, writing a
/// flat command buffer (through the same `RingBuffer` primitive `good` uses
/// for the command queue, obtained via `Game.describeBuffers`) once per fixed
/// tick; the main isolate's [DrawCanvas2D] only replays it. That is also why
/// every record's geometry is already finalized - world space, hierarchy
/// already flattened, rotation and scale already baked into the corner
/// coordinates - there is no `Canvas.save`/`restore`/`translate`/`rotate`
/// call anywhere in this pipeline, per the draw-batch rule.
///
/// # Two shapes this file deliberately does *not* have
///
/// **No object per drawn thing.** The original sketch here had
/// `DrawData2D.draw(Canvas)` - one instance per sprite, each drawing itself.
/// That loses twice: it allocates one object per sprite per frame on a 60 Hz
/// path (the no-allocation rule), and it forces one `Canvas` call per sprite, which
/// is exactly the per-draw overhead batching exists to avoid. So [DrawData2D]
/// here is one instance per *kind* of record - a codec, effectively a
/// singleton - and the per-sprite data never becomes a Dart object at all: it
/// goes bytes -> [VertexBatch2D]'s typed lists -> one `drawVertices` per
/// contiguous run of sprites sharing a texture (see [DrawCanvas2D]).
///
/// **No record per drawn thing either.** One `RingBuffer` record per sprite
/// would make `RingBuffer.drainInto` allocate a `RingBufferRecord` *and* a
/// `Uint8List` view per sprite per frame - the same rule-1 problem one step
/// down. Instead each tick writes **one record per draw-data type**, whose
/// payload is a tick stamp followed by a packed array of that type's
/// fixed-size items. Two things fall out of that for free: the drain cost is
/// O(record types) rather than O(sprites), and a tick stamp on every record
/// lets the consumer identify the newest complete frame and skip stale ones
/// when the main isolate has fallen behind the simulation (see
/// [DrawCanvas2D.ingest]).
library;

import 'dart:typed_data';
import 'dart:ui';

import 'package:good/good.dart';
import 'package:goo2d/src/render/texture.dart';

/// One *kind* of draw record: its ring-buffer record type, the size of one
/// item in its packed payload, and how a drained batch of those items turns
/// into geometry.
///
/// Not a per-drawn-thing object - see the library doc. Instances are stateless
/// singletons registered in a [DrawRegistry2D]; the writing half lives on the
/// concrete subclass as a static packer (see [DrawSpriteData2D.writeQuad])
/// because the game isolate writes straight into a scratch `ByteData` and
/// never needs the codec object at all.
abstract class DrawData2D {
  const DrawData2D();

  /// Every batch payload starts with an `int64` tick stamp - the fixed tick
  /// whose simulation state it depicts. See [DrawCanvas2D.ingest].
  static const int batchHeaderBytes = 8;

  /// Reads the tick stamp off a batch payload.
  static int batchTick(ByteData batch) => batch.getInt64(0, Endian.little);

  /// Writes the tick stamp; the packer for this type's items starts at
  /// [batchHeaderBytes].
  static void writeBatchTick(ByteData batch, int tick) =>
      batch.setInt64(0, tick, Endian.little);

  /// Number of items in a batch payload of [byteLength] bytes.
  int itemCount(int byteLength) =>
      (byteLength - batchHeaderBytes) ~/ itemStrideBytes;

  /// The tag in the ring record's header - what routes a drained record back
  /// to this codec. Unique across a [DrawRegistry2D]; note `RingBuffer`
  /// reserves -1 internally for its wrap padding record.
  int get recordType;

  /// Bytes per item in a batch payload. Fixed, which is what makes
  /// [itemCount] derivable and the packer a plain indexed write.
  int get itemStrideBytes;

  /// Appends [count] items' worth of triangles to [out]. Runs on the main
  /// isolate, once per new frame - not once per paint (see [DrawCanvas2D]).
  void buildGeometry(ByteData batch, int count, VertexBatch2D out);
}

/// A world-space quad: four already-transformed corners, one ARGB colour, the
/// texture it samples, one UV pair per corner, and how it samples. 76 bytes.
///
/// # Layout
///
/// ```text
///  0 .. 31   4 corners x (float32 x, float32 y)   world space, winding order
/// 32 .. 35   uint32  ARGB                          tint (or fill, untextured)
/// 36 .. 39   int32   texture address               [noTexture] when untextured
/// 40 .. 71   4 corners x (float32 u, float32 v)   normalised 0..1
/// 72 .. 75   int32   texture filter                [TextureFilter] index
/// ```
///
/// The colour keeps byte 32 and the corners keep bytes 0..31 on purpose: the
/// textured fields are strictly appended, so every existing hand-decoder that
/// reads a corner or a colour by offset stays correct and only the stride
/// moved.
///
/// **The texture is an address, never a `ui.Image`.** The producer runs on the
/// game isolate, which has no Flutter engine and whose `Texture` copies are
/// declared-but-never-decoded (see `Texture`'s own doc). What crosses the ring
/// is the `GlobalObject` registry address - the same integer on both isolates,
/// because both ran the same `describeAssets` pass in the same order - and
/// [DrawCanvas2D] turns it back into a live `Texture` with
/// the asset table's `resolve` at replay time.
///
/// Corners and UVs are stored as `float32`, not the `float64` the transform
/// fields use: `Vertices.raw` takes `Float32List`s, so anything wider would be
/// narrowed on the way into the vertex buffer regardless, and this halves the
/// bytes crossing the ring.
final class DrawSpriteData2D extends DrawData2D {
  const DrawSpriteData2D();

  static const int spriteRecordType = 0;

  /// The texture-address value meaning "this quad samples nothing - draw the
  /// flat colour".
  ///
  /// **`-1`, not `0`.** An `ObjectTable` hands out addresses
  /// from a plain append-only list starting at zero, so `0` is the address of
  /// whichever asset a process declared first - a perfectly ordinary,
  /// resolvable texture. Using it as "none" would make the first texture ever
  /// declared invisible, and the failure would look like an asset bug rather
  /// than an encoding one. `-1` is never handed out (the registry only ever
  /// appends), which is why the field is a signed `int32` rather than the
  /// `uint32` a bare address would need.
  static const int noTexture = -1;

  /// 4 corners x (float32 x, float32 y) + uint32 ARGB + int32 texture address
  /// + 4 corners x (float32 u, float32 v) + int32 texture filter.
  static const int strideBytes = 76;

  /// Packs one quad at [offset] and returns the offset of the next item.
  ///
  /// Corners are in winding order - `(x0,y0)` and `(x2,y2)` are opposite -
  /// which is what lets [buildGeometry] triangulate without inspecting them.
  /// The UV pairs are in that same corner order, so `(u1,v1)` belongs to
  /// `(x1,y1)`.
  ///
  /// The UV defaults spell the whole-texture case - `(0,0) (1,0) (1,1) (0,1)`
  /// - which is what a plain textured sprite wants and what an untextured one
  /// harmlessly carries; the atlas/nine-slice cases pass their own. Named
  /// optional parameters rather than a value object holding eight doubles,
  /// because this is called once per sprite per tick and an argument object
  /// there is exactly the per-sprite heap allocation the no-allocation rule forbids
  /// (named arguments on a statically-resolved call allocate nothing).
  static int writeQuad(
    ByteData batch,
    int offset,
    double x0,
    double y0,
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
    int argb, {
    int textureAddress = noTexture,
    /// A [TextureFilter] index. An `int` rather than the enum because this is
    /// the wire format: the producer already holds the index (it read one out
    /// of a row) and only [DrawCanvas2D] ever turns it back into a
    /// `FilterQuality`, once per run.
    int filter = 0,
    double u0 = 0,
    double v0 = 0,
    double u1 = 1,
    double v1 = 0,
    double u2 = 1,
    double v2 = 1,
    double u3 = 0,
    double v3 = 1,
  }) {
    batch
      ..setFloat32(offset, x0, Endian.little)
      ..setFloat32(offset + 4, y0, Endian.little)
      ..setFloat32(offset + 8, x1, Endian.little)
      ..setFloat32(offset + 12, y1, Endian.little)
      ..setFloat32(offset + 16, x2, Endian.little)
      ..setFloat32(offset + 20, y2, Endian.little)
      ..setFloat32(offset + 24, x3, Endian.little)
      ..setFloat32(offset + 28, y3, Endian.little)
      ..setUint32(offset + 32, argb, Endian.little)
      ..setInt32(offset + 36, textureAddress, Endian.little)
      ..setFloat32(offset + 40, u0, Endian.little)
      ..setFloat32(offset + 44, v0, Endian.little)
      ..setFloat32(offset + 48, u1, Endian.little)
      ..setFloat32(offset + 52, v1, Endian.little)
      ..setFloat32(offset + 56, u2, Endian.little)
      ..setFloat32(offset + 60, v2, Endian.little)
      ..setFloat32(offset + 64, u3, Endian.little)
      ..setFloat32(offset + 68, v3, Endian.little)
      ..setInt32(offset + 72, filter, Endian.little);
    return offset + strideBytes;
  }

  /// Reads back the texture address of item [index] - the reader half of
  /// [writeQuad]'s texture field, so a decoder never re-derives the offset.
  static int textureAddressAt(ByteData batch, int index) => batch.getInt32(
    DrawData2D.batchHeaderBytes + index * strideBytes + 36,
    Endian.little,
  );

  /// Reads back the [TextureFilter] index of item [index]. Same reasoning as
  /// [textureAddressAt].
  static int filterAt(ByteData batch, int index) => batch.getInt32(
    DrawData2D.batchHeaderBytes + index * strideBytes + 72,
    Endian.little,
  );

  @override
  int get recordType => spriteRecordType;

  @override
  int get itemStrideBytes => strideBytes;

  @override
  void buildGeometry(ByteData batch, int count, VertexBatch2D out) {
    var offset = DrawData2D.batchHeaderBytes;
    for (var i = 0; i < count; i++) {
      out.addQuad(
        batch.getFloat32(offset, Endian.little),
        batch.getFloat32(offset + 4, Endian.little),
        batch.getFloat32(offset + 8, Endian.little),
        batch.getFloat32(offset + 12, Endian.little),
        batch.getFloat32(offset + 16, Endian.little),
        batch.getFloat32(offset + 20, Endian.little),
        batch.getFloat32(offset + 24, Endian.little),
        batch.getFloat32(offset + 28, Endian.little),
        batch.getUint32(offset + 32, Endian.little),
        textureAddress: batch.getInt32(offset + 36, Endian.little),
        u0: batch.getFloat32(offset + 40, Endian.little),
        v0: batch.getFloat32(offset + 44, Endian.little),
        u1: batch.getFloat32(offset + 48, Endian.little),
        v1: batch.getFloat32(offset + 52, Endian.little),
        u2: batch.getFloat32(offset + 56, Endian.little),
        v2: batch.getFloat32(offset + 60, Endian.little),
        u3: batch.getFloat32(offset + 64, Endian.little),
        v3: batch.getFloat32(offset + 68, Endian.little),
        filter: batch.getInt32(offset + 72, Endian.little),
      );
      offset += strideBytes;
    }
  }
}

/// Maps a drained record's type tag back to the codec that understands it.
///
/// Third parties deliberately cannot add draw-data types: every type has to
/// agree byte-for-byte across the isolate boundary and share the one
/// `drawVertices` batch, so the set is closed and small. [standard] is the
/// only registry anything currently needs; the class exists so a second
/// pipeline (an editor overlay, a debug pass) can carry a different set
/// without a global.
final class DrawRegistry2D {
  DrawRegistry2D();

  /// Every draw-data type this package defines.
  static final DrawRegistry2D standard = DrawRegistry2D()
    ..register(const DrawSpriteData2D());

  final Map<int, DrawData2D> _byRecordType = <int, DrawData2D>{};

  void register(DrawData2D type) {
    final existing = _byRecordType[type.recordType];
    if (existing != null) {
      throw StateError(
        'Draw record type ${type.recordType} is registered twice: '
        '${existing.runtimeType} and ${type.runtimeType}.',
      );
    }
    _byRecordType[type.recordType] = type;
  }

  /// The codec for [recordType], or null if this registry does not know it -
  /// which a consumer treats as "skip", not as an error, so an older build of
  /// the main isolate can keep painting the record types it does understand.
  DrawData2D? operator [](int recordType) => _byRecordType[recordType];
}

/// A reusable triangle-soup accumulator: positions, per-vertex colours and
/// per-vertex texture coordinates in the exact layout `Vertices.raw` wants,
/// plus the run table that says which texture each stretch of vertices samples.
///
/// Lives across frames and is only ever refilled, so a steady-state frame
/// allocates nothing here at all - the typed lists grow to the high-water mark
/// of the scene and stay there. That is the whole reason geometry is built into
/// this rather than into a fresh list per frame (the no-allocation rule).
///
/// # Runs, and why they are not a group-by
///
/// Quads arrive **already z-sorted** (`GameRenderer2D` sorted them before
/// writing the record), and the painter's algorithm means the order they are
/// drawn in *is* the depth. So this does not group quads by texture: it starts
/// a new run every time [addQuad] is handed a different texture address from
/// the previous quad's, and never reorders anything. Two quads sharing a
/// texture merge into one run only when they are already adjacent in draw
/// order.
///
/// The cost of that is real and deliberate: a scene whose textures alternate
/// A-B-A-B produces one run - and therefore one `drawVertices` - per quad. The
/// alternative (one run per distinct texture across the whole frame) would cut
/// that to two calls and silently reorder overlapping sprites, turning a
/// batching optimisation into a rendering bug. Anything that wants both has to
/// fix it upstream where the information is - a texture atlas, so the sprites
/// genuinely share a texture, or a z assignment that keeps same-texture sprites
/// adjacent - not here, where reordering is unobservably wrong.
final class VertexBatch2D {
  VertexBatch2D({int initialQuadCapacity = 64})
    : _positions = Float32List(initialQuadCapacity * _verticesPerQuad * 2),
      _colors = Int32List(initialQuadCapacity * _verticesPerQuad),
      _texCoords = Float32List(initialQuadCapacity * _verticesPerQuad * 2),
      _runTextures = Int32List(initialQuadCapacity),
      _runFilters = Int32List(initialQuadCapacity),
      _runVertexEnds = Int32List(initialQuadCapacity);

  /// Two triangles, no index buffer. An indexed `Vertices` would save a third
  /// of the vertex data but costs an `Uint16List` of its own plus a 65535
  /// vertex ceiling to manage; at 6 floats per quad saved, that trade is not
  /// worth making before anything measures it.
  static const int _verticesPerQuad = 6;

  Float32List _positions;
  Int32List _colors;
  Float32List _texCoords;
  int _vertexCount = 0;

  /// Texture address per run, and the exclusive vertex index each run ends at.
  /// Parallel arrays rather than a list of run objects, for the reason every
  /// other buffer here is: one object per run per frame is a per-frame heap
  /// allocation proportional to the scene.
  Int32List _runTextures;

  /// Filter per run. A run is one `drawVertices` call under one `Paint`, and
  /// the filter lives on the paint - so two adjacent quads sharing a texture
  /// but sampling it differently genuinely cannot share a run.
  Int32List _runFilters;
  Int32List _runVertexEnds;
  int _runCount = 0;

  int get vertexCount => _vertexCount;

  /// How many contiguous same-texture stretches the current contents split
  /// into - i.e. how many `drawVertices` calls [DrawCanvas2D.replay] will make.
  int get runCount => _runCount;

  /// The texture address run [run] samples, or [DrawSpriteData2D.noTexture].
  int runTextureAt(int run) => _runTextures[run];

  /// The [TextureFilter] index run [run] samples with.
  int runFilterAt(int run) => _runFilters[run];

  /// First vertex of run [run].
  int runVertexStart(int run) => run == 0 ? 0 : _runVertexEnds[run - 1];

  /// One past the last vertex of run [run].
  int runVertexEnd(int run) => _runVertexEnds[run];

  /// The filled prefix of the position buffer - `x, y` per vertex. A view,
  /// not a copy; valid until the next [addQuad] that has to grow.
  Float32List get positions =>
      Float32List.sublistView(_positions, 0, _vertexCount * 2);

  /// The filled prefix of the colour buffer - one packed ARGB per vertex.
  ///
  /// `Int32List`, because that is what `Vertices.raw` takes, so an opaque
  /// colour reads back *negative* here: `0xFF00FF00` is stored as the
  /// identical 32 bits and interpreted as -16711936. Only the bit pattern
  /// reaches the engine, so nothing needs converting - but compare against
  /// `.toUnsigned(32)` if you ever read one of these back.
  Int32List get colors => Int32List.sublistView(_colors, 0, _vertexCount);

  /// The filled prefix of the texture-coordinate buffer - `u, v` per vertex,
  /// normalised 0..1. Meaningless for vertices in an untextured run, which
  /// carry whatever the producer wrote and never reach a shader.
  Float32List get texCoords =>
      Float32List.sublistView(_texCoords, 0, _vertexCount * 2);

  void reset() {
    _vertexCount = 0;
    _runCount = 0;
  }

  /// Appends the two triangles of quad `(0,1,2,3)`, all six vertices tinted
  /// [argb] and sampling [textureAddress]. Corners must be in winding order,
  /// and the UV pairs are in that same corner order.
  ///
  /// Extends the open run when [textureAddress] matches the previous quad's
  /// and opens a new one when it does not - see the class doc on why that is
  /// a run boundary rather than a group-by.
  void addQuad(
    double x0,
    double y0,
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
    int argb, {
    int textureAddress = DrawSpriteData2D.noTexture,
    int filter = 0,
    double u0 = 0,
    double v0 = 0,
    double u1 = 1,
    double v1 = 0,
    double u2 = 1,
    double v2 = 1,
    double u3 = 0,
    double v3 = 1,
  }) {
    _ensure(_vertexCount + _verticesPerQuad);
    var p = _vertexCount * 2;
    var c = _vertexCount;
    var t = _vertexCount * 2;
    final positions = _positions;
    final colors = _colors;
    final texCoords = _texCoords;
    // 0,1,2 then 0,2,3 - the standard fan split of a convex quad. The UVs
    // follow the identical split so vertex n's coordinate always belongs to
    // vertex n's position.
    positions[p++] = x0;
    positions[p++] = y0;
    positions[p++] = x1;
    positions[p++] = y1;
    positions[p++] = x2;
    positions[p++] = y2;
    positions[p++] = x0;
    positions[p++] = y0;
    positions[p++] = x2;
    positions[p++] = y2;
    positions[p++] = x3;
    positions[p++] = y3;
    texCoords[t++] = u0;
    texCoords[t++] = v0;
    texCoords[t++] = u1;
    texCoords[t++] = v1;
    texCoords[t++] = u2;
    texCoords[t++] = v2;
    texCoords[t++] = u0;
    texCoords[t++] = v0;
    texCoords[t++] = u2;
    texCoords[t++] = v2;
    texCoords[t++] = u3;
    texCoords[t++] = v3;
    for (var i = 0; i < _verticesPerQuad; i++) {
      colors[c++] = argb;
    }
    _vertexCount += _verticesPerQuad;
    if (_runCount == 0 ||
        _runTextures[_runCount - 1] != textureAddress ||
        _runFilters[_runCount - 1] != filter) {
      _runTextures[_runCount] = textureAddress;
      _runFilters[_runCount] = filter;
      _runCount++;
    }
    _runVertexEnds[_runCount - 1] = _vertexCount;
  }

  void _ensure(int vertices) {
    // One quad can open at most one run, so run capacity tracks quad capacity
    // and the two grow together.
    if (vertices * 2 <= _positions.length) return;
    var capacity = _positions.length ~/ 2;
    while (capacity < vertices) {
      capacity *= 2;
    }
    _positions = Float32List(capacity * 2)
      ..setRange(0, _vertexCount * 2, _positions);
    _colors = Int32List(capacity)..setRange(0, _vertexCount, _colors);
    _texCoords = Float32List(capacity * 2)
      ..setRange(0, _vertexCount * 2, _texCoords);
    final runs = capacity ~/ _verticesPerQuad + 1;
    _runTextures = Int32List(runs)..setRange(0, _runCount, _runTextures);
    _runFilters = Int32List(runs)..setRange(0, _runCount, _runFilters);
    _runVertexEnds = Int32List(runs)..setRange(0, _runCount, _runVertexEnds);
  }

  /// Builds the immutable `Vertices` for run [run] - the geometry of exactly
  /// one `drawVertices` call.
  ///
  /// Allocates: a `Vertices` (an immutable native mesh - there is no reusable
  /// form of it in `dart:ui`) plus the typed-list views describing the run's
  /// slice. Both are per *frame*, not per paint - [DrawCanvas2D] holds the
  /// built meshes and only rebuilds when a new frame has been ingested.
  ///
  /// An untextured run is built without texture coordinates at all rather than
  /// with ignored ones: the paint that draws it has no shader, so coordinates
  /// would be dead weight crossing into the engine on every frame.
  Vertices buildRun(int run) {
    final start = runVertexStart(run);
    final end = _runVertexEnds[run];
    final runPositions = Float32List.sublistView(
      _positions,
      start * 2,
      end * 2,
    );
    final runColors = Int32List.sublistView(_colors, start, end);
    if (_runTextures[run] == DrawSpriteData2D.noTexture) {
      return Vertices.raw(
        VertexMode.triangles,
        runPositions,
        colors: runColors,
      );
    }
    return Vertices.raw(
      VertexMode.triangles,
      runPositions,
      textureCoordinates: Float32List.sublistView(
        _texCoords,
        start * 2,
        end * 2,
      ),
      colors: runColors,
    );
  }
}

/// The main-isolate side of the render pipeline: turns drained draw records
/// into geometry, then replays that geometry onto a `Canvas`.
///
/// Never mutates game state, never runs a query, never touches an `Entity` -
/// everything it needs is in the bytes the game isolate published. The two
/// halves run at different rates on purpose:
///
///  * [ingest] runs once per tick notification (see `GameView`), decodes the
///    newest complete frame into the persistent [VertexBatch2D], and reports
///    whether anything changed. This is where all the per-sprite work is.
///  * [replay] runs once per paint and does exactly two things: build the
///    `Vertices` if the frame moved since last time, and issue one
///    `drawVertices` **per texture run** (see below). No `save`, `restore`,
///    `translate`, `rotate` or `drawImage` - the draw-batch rule, enforced by a spy
///    `Canvas` in `test/draw_canvas_2d_test.dart` rather than only promised
///    here.
///
/// # How a texture gets sampled without `drawImage`
///
/// Rule 3 forbids `Canvas.drawImage` and the whole matrix stack, which rules
/// out every ordinary way of putting an image on screen. What is left, and what
/// this uses, is `drawVertices` with per-vertex texture coordinates and a
/// `Paint` whose shader is an [ImageShader] over the texture: the mesh carries
/// the UVs, the shader carries the pixels, and the canvas is never asked to
/// transform or blit anything. The quads' corners are already in world space,
/// so there is nothing for a matrix stack to do either.
///
/// The shader's local matrix is `scale(1/width, 1/height)`, which is what makes
/// the normalised 0..1 UVs in the record address the whole image: an
/// `ImageShader`'s matrix maps image space into the coordinate space the
/// texture coordinates are expressed in, so shrinking the image to a unit
/// square is exactly the change that makes `(1,1)` mean "bottom-right corner"
/// instead of "pixel (1,1)". That keeps the wire format resolution-independent
/// - the producer never learns a texture's pixel size, which it could not do
/// anyway on an isolate that never decodes one.
///
/// Shaders are built **once per texture** and cached here for the life of this
/// canvas, because constructing one uploads and binds engine-side state; doing
/// it per frame (let alone per quad) at compositor rate is precisely the
/// hot-path allocation the no-allocation rule exists for. [dispose] releases
/// them.
///
/// # Why batching does not reorder anything
///
/// The quads arrive z-sorted and the painter's algorithm makes draw order the
/// depth, so [VertexBatch2D] cuts a new run wherever the texture changes rather
/// than grouping the frame by texture. See its class doc for the trade that
/// buys and the alternating-texture case that pays for it.
final class DrawCanvas2D {
  DrawCanvas2D({required this.assets, DrawRegistry2D? registry})
    : registry = registry ?? DrawRegistry2D.standard {
    // Registered here rather than from a `GameSystem.onMounted`, which is
    // where it used to live and which was the wrong isolate *and* an
    // undispatched hook: systems run on the game isolate, which never decodes
    // anything and therefore never needs a loader, while the copy that does
    // decode was never told. A canvas is constructed only on the isolate with
    // Flutter attached, and always before anything it draws is decoded, so it
    // is the one place that is both necessary and sufficient.
    //
    // Idempotent - `register` replaces, and the loader is `const`.
    AssetLoaders.register<Texture>(const TextureLoader());
  }

  final DrawRegistry2D registry;

  /// The table a record's texture address resolves through - **the `Game`'s**.
  ///
  /// This is the main-isolate end of the asset architecture: the game isolate
  /// holds payload-free declarations and emits draw records naming an
  /// *address*, and this side owns the decoded `ui.Image` and resolves the
  /// address at draw time. It is passed in rather than reached statically
  /// because the table is instance state on the `Game` now, which is also what
  /// lets it cross `Isolate.spawn` with the rest of the object graph.
  final Assets assets;

  final VertexBatch2D _batch = VertexBatch2D();

  /// White and shaderless. With [BlendMode.dst] the vertex colours are what
  /// survives the blend, so this paint contributes only its (default) anti
  /// aliasing and blend behaviour - the per-quad colours in the batch are the
  /// actual colour source. Untextured runs only.
  final Paint _paint = Paint();

  /// One ready-to-use shader `Paint` per texture address, built lazily on the
  /// first frame that draws that texture and kept until [dispose].
  ///
  /// A `Map` that is *never rebuilt* - grouping a frame through a fresh map
  /// would be the per-frame allocation rule 1 forbids, but a persistent cache
  /// keyed by an `int` costs nothing to read and is the only thing standing
  /// between this and an `ImageShader` per frame.
  final Map<int, Paint> _texturePaints = <int, Paint>{};

  /// The built mesh per run, index-parallel to [VertexBatch2D]'s runs, reused
  /// across frames: the list grows to the scene's high-water mark and its
  /// entries are replaced (and the old ones disposed) when a frame is ingested.
  final List<Vertices?> _runVertices = <Vertices?>[];
  int _runCount = 0;

  bool _verticesStale = true;
  int _frameTick = -1;

  /// The fixed tick the currently-held frame depicts, or -1 before the first
  /// frame arrives.
  int get frameTick => _frameTick;

  /// Whether [replay] would draw anything.
  bool get hasFrame => _frameTick >= 0;

  int get vertexCount => _batch.vertexCount;

  /// The held frame's geometry - `x, y` per vertex, and one packed ARGB per
  /// vertex. Views over the live buffers, valid until the next [ingest];
  /// exposed because `Vertices` is write-only once built (dart:ui hands back
  /// no way to read it), so this is the only way anything - a test, a debug
  /// overlay - can see what [replay] is about to draw.
  Float32List get positions => _batch.positions;
  Int32List get colors => _batch.colors;

  /// `u, v` per vertex, normalised 0..1. Vertices belonging to an untextured
  /// run carry values no shader will ever read.
  Float32List get texCoords => _batch.texCoords;

  /// Adopts the newest complete frame in [records] and returns whether that
  /// changed what [replay] would draw.
  ///
  /// [records] is a whole drain, which may hold several ticks' worth if the
  /// main isolate fell behind the simulation. Every record carries the tick it
  /// belongs to, so this takes the highest tick present and ignores the rest:
  /// showing a stale frame that a newer one in the same drain supersedes would
  /// be pure latency. An *older* tick than the one already held is ignored
  /// too, which cannot normally happen but keeps a duplicate drain harmless.
  ///
  /// Returns false when the drain held nothing this registry understands, or
  /// nothing newer - which is what lets `GameView` skip the repaint instead of
  /// marking dirty on every tick unconditionally.
  bool ingest(List<RingBufferRecord> records) {
    var newest = _frameTick;
    for (var i = 0; i < records.length; i++) {
      final record = records[i];
      if (registry[record.recordType] == null) continue;
      final tick = DrawData2D.batchTick(ByteData.sublistView(record.payload));
      if (tick > newest) newest = tick;
    }
    if (newest <= _frameTick) return false;

    _batch.reset();
    for (var i = 0; i < records.length; i++) {
      final record = records[i];
      final type = registry[record.recordType];
      if (type == null) continue;
      final batch = ByteData.sublistView(record.payload);
      if (DrawData2D.batchTick(batch) != newest) continue;
      type.buildGeometry(batch, type.itemCount(record.payload.length), _batch);
    }
    _frameTick = newest;
    _verticesStale = true;
    return true;
  }

  /// [ingest], for a frame that arrived through a `HandoffBuffer` rather than
  /// a ring drain: one batch, already known to be the newest complete one.
  ///
  /// [byteLength] is what the writer published as used, not the slot's
  /// capacity - decoding the whole slot would walk whatever the previous,
  /// busier frame left in the tail.
  ///
  /// **One batch of one codec per slot.** The ring form above could carry a
  /// drain holding several record types; a slot holds exactly what fits, and
  /// it is sized for sprites. A second codec (particles, lines) wants its own
  /// handoff buffer rather than a section header in this one - separate
  /// producers, separate rates, no reason to couple them.
  bool ingestFrame(ByteData batch, int byteLength) {
    final tick = DrawData2D.batchTick(batch);
    // Older or equal means the reader sampled faster than the writer
    // published, which is the normal case at 60Hz against a slower tick. There
    // is nothing new to build; repaint what is already held.
    if (tick <= _frameTick) return false;

    final type = registry[DrawSpriteData2D.spriteRecordType];
    if (type == null) return false;
    _batch.reset();
    type.buildGeometry(batch, type.itemCount(byteLength), _batch);
    _frameTick = tick;
    _verticesStale = true;
    return true;
  }

  /// How many `drawVertices` calls [replay] will make for the held frame -
  /// one per contiguous same-texture run, not one per sprite and not one per
  /// distinct texture.
  int get runCount => _batch.runCount;

  /// The texture address run [run] samples, or [DrawSpriteData2D.noTexture].
  int runTextureAt(int run) => _batch.runTextureAt(run);

  /// The [TextureFilter] index run [run] samples with.
  int runFilterAt(int run) => _batch.runFilterAt(run);

  /// Replays the held frame: one `drawVertices` per texture run, in run order,
  /// which is z order - see the class doc.
  void replay(Canvas canvas) {
    // Rebuild first even when the frame is empty: that is what disposes the
    // meshes the previous, non-empty frame left behind. An emptied scene then
    // costs zero draw calls because `_runCount` is zero, not because of a
    // guard that would have skipped the cleanup.
    if (_verticesStale) _rebuildRuns();
    for (var run = 0; run < _runCount; run++) {
      final vertices = _runVertices[run]!;
      final address = _batch.runTextureAt(run);
      if (address == DrawSpriteData2D.noTexture) {
        // BlendMode.dst: the vertices are the destination, the paint the
        // source, so "keep destination" is what makes the per-quad colours the
        // ones that land.
        canvas.drawVertices(vertices, BlendMode.dst, _paint);
      } else {
        // BlendMode.modulate multiplies source by destination - the sampled
        // texel by the per-vertex colour - so `Sprite.color` acts as a tint and
        // the default opaque white leaves the texture exactly as decoded.
        final paint = _paintFor(address, _batch.runFilterAt(run));
        // Null means the texture is declared but has not finished decoding on
        // this isolate yet. Skipping the run drops it for exactly the frames
        // that race the decode - see [_paintFor].
        if (paint != null) {
          canvas.drawVertices(vertices, BlendMode.modulate, paint);
        }
      }
    }
  }

  /// Rebuilds one `Vertices` per run, disposing the meshes the previous frame
  /// left behind. Runs at most once per ingested frame, never per paint.
  void _rebuildRuns() {
    for (var i = 0; i < _runCount; i++) {
      _runVertices[i]?.dispose();
      _runVertices[i] = null;
    }
    _runCount = _batch.runCount;
    while (_runVertices.length < _runCount) {
      _runVertices.add(null);
    }
    for (var run = 0; run < _runCount; run++) {
      _runVertices[run] = _batch.buildRun(run);
    }
    _verticesStale = false;
  }

  /// The cached shader `Paint` for [address], building it on first use.
  ///
  /// `resolve` still throws when the address names nothing on this isolate: a
  /// stale record is a real bug, and the alternative is sampling nothing and
  /// painting silent garbage, which is the kind that takes a day to find.
  ///
  /// **Declared-but-not-yet-decoded is different, and returns null instead.**
  /// It is not a bug at all - it is the ordinary state of the first frames of a
  /// run. The simulation starts producing batches as soon as its scene mounts,
  /// while the bytes are decoded over here on main and arrive a few frames
  /// later, so a batch naming a texture main has not finished with is expected
  /// and transient. Throwing on it took the whole app down the moment a case
  /// had entities on its very first frame - which switching cases in the demo
  /// menu did every time, and which read as "stuck on loading" because the
  /// exception escaped from a painter rather than from the load.
  ///
  /// Skipping the run means those frames draw without that texture and the
  /// next one draws normally. Nothing is silently wrong: the asset either
  /// finishes decoding, or its load fails and reports that where the failure
  /// actually is.
  Paint? _paintFor(int address, int filter) {
    // Keyed by texture *and* filter: the filter lives on the `Paint`, so one
    // texture drawn crisply in one sprite and smoothly in another needs two.
    // Packed into one int rather than a record key because this is a map
    // lookup on the paint path - once per run, not per quad, but a record key
    // would allocate there for nothing. Three bits is room for every
    // `TextureFilter` there will be; an asset address never approaches 2^28.
    final key = (address << 3) | filter;
    final cached = _texturePaints[key];
    if (cached != null) return cached;
    final asset = assets.of<Texture>().unpack(address);
    if (!asset.isLoaded) return null;
    final image = asset.value.image;
    // scale(1/w, 1/h): maps the image onto the unit square, so the record's
    // normalised UVs address it whatever its pixel size. See the class doc.
    final matrix = Float64List(16);
    matrix[0] = 1 / image.width;
    matrix[5] = 1 / image.height;
    matrix[10] = 1;
    matrix[15] = 1;
    // `filterQuality` matters more here than it would on `drawImageRect`,
    // because a sprite is routinely drawn much smaller than its source image.
    // Omitting it defaults to nearest sampling, and a minified sprite then
    // *shimmers* as it moves, because which texel gets picked changes with
    // sub-pixel position. That reads as "the art is low resolution" rather
    // than as a filtering setting - which is exactly why it is declared per
    // texture now instead of left to a default nobody can see.
    final paint = Paint()
      ..shader = ImageShader(
        image,
        TileMode.clamp,
        TileMode.clamp,
        matrix,
        filterQuality: TextureFilter.values[filter].quality,
      );
    _texturePaints[key] = paint;
    return paint;
  }

  void dispose() {
    for (var i = 0; i < _runCount; i++) {
      _runVertices[i]?.dispose();
      _runVertices[i] = null;
    }
    _runCount = 0;
    for (final paint in _texturePaints.values) {
      paint.shader?.dispose();
    }
    _texturePaints.clear();
    _verticesStale = true;
  }
}
