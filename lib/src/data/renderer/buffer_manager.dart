import 'dart:typed_data';

/// Manages a set of triple-buffered (or depth-configurable) typed-data buffers
/// used for zero-copy batched [drawVertices] rendering.
///
/// A single static [instance] is shared between the EC and ECS render paths.
/// [rotate] is called once per frame after all [drawVertices] calls are issued,
/// so the GPU can finish reading the submitted slot before it is overwritten.
class BufferManager {
  static BufferManager instance = BufferManager._();

  final int depth;

  int _current = 0;
  int get current => _current;

  int _vertexWriteCursor = 0;
  int _indexWriteCursor = 0;

  int _vertexCapacity = 0;
  int _indexCapacity = 0;

  late List<Float32List> _positions; // 2 floats per vertex (x, y)
  late List<Float32List> _uvs;       // 2 floats per vertex (u, v)
  late List<Int32List>   _colors;    // 1 ARGB int per vertex
  late List<Uint16List>  _indices;

  BufferManager._({this.depth = 3, int initialVertices = 1024, int initialIndices = 1536}) {
    _vertexCapacity = initialVertices;
    _indexCapacity  = initialIndices;
    _positions = List.generate(depth, (_) => Float32List(initialVertices * 2));
    _uvs       = List.generate(depth, (_) => Float32List(initialVertices * 2));
    _colors    = List.generate(depth, (_) => Int32List(initialVertices));
    _indices   = List.generate(depth, (_) => Uint16List(initialIndices));
  }

  /// Replace the global instance — useful in tests or to change buffer depth.
  static void configure({int depth = 3, int initialVertices = 1024, int initialIndices = 1536}) {
    instance = BufferManager._(
      depth: depth,
      initialVertices: initialVertices,
      initialIndices: initialIndices,
    );
  }

  // ---------------------------------------------------------------------------
  // Write accessors — direct references to the current slot's lists.
  // ---------------------------------------------------------------------------

  Float32List get currentPositions => _positions[_current];
  Float32List get currentUvs       => _uvs[_current];
  Int32List   get currentColors    => _colors[_current];
  Uint16List  get currentIndices   => _indices[_current];

  /// Current write cursor position (in vertices) for vertex buffers.
  int get vertexWriteCursor => _vertexWriteCursor;

  /// Current write cursor position for the index buffer.
  int get indexWriteCursor => _indexWriteCursor;

  // ---------------------------------------------------------------------------
  // Reserve
  // ---------------------------------------------------------------------------

  /// Reserves space for [vertexCount] vertices and [indexCount] indices in the
  /// current buffer slot. Returns the vertex base offset to use when writing.
  ///
  /// Grows all slots if needed (amortised O(1)).
  int reserve(int vertexCount, int indexCount) {
    final vb = _vertexWriteCursor;
    _vertexWriteCursor += vertexCount;
    _indexWriteCursor  += indexCount;
    _ensureCapacity(_vertexWriteCursor, _indexWriteCursor);
    return vb;
  }

  void _ensureCapacity(int neededV, int neededI) {
    var grewV = false;
    var grewI = false;
    while (_vertexCapacity < neededV) { _vertexCapacity *= 2; grewV = true; }
    while (_indexCapacity  < neededI) { _indexCapacity  *= 2; grewI = true; }
    if (!grewV && !grewI) return;
    for (var i = 0; i < depth; i++) {
      if (grewV) {
        _positions[i] = Float32List(_vertexCapacity * 2)
          ..setRange(0, _positions[i].length, _positions[i]);
        _uvs[i] = Float32List(_vertexCapacity * 2)
          ..setRange(0, _uvs[i].length, _uvs[i]);
        _colors[i] = Int32List(_vertexCapacity)
          ..setRange(0, _colors[i].length, _colors[i]);
      }
      if (grewI) {
        _indices[i] = Uint16List(_indexCapacity)
          ..setRange(0, _indices[i].length, _indices[i]);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Zero-copy views — use Float32List.sublistView to avoid allocation.
  // ---------------------------------------------------------------------------

  Float32List positionsView(int vertexBase, int count) =>
      Float32List.sublistView(_positions[_current], vertexBase * 2, (vertexBase + count) * 2);

  Float32List uvsView(int vertexBase, int count) =>
      Float32List.sublistView(_uvs[_current], vertexBase * 2, (vertexBase + count) * 2);

  Int32List colorsView(int vertexBase, int count) =>
      Int32List.sublistView(_colors[_current], vertexBase, vertexBase + count);

  Uint16List indicesView(int indexBase, int count) =>
      Uint16List.sublistView(_indices[_current], indexBase, indexBase + count);

  // ---------------------------------------------------------------------------
  // Frame lifecycle
  // ---------------------------------------------------------------------------

  void resetCursors() {
    _vertexWriteCursor = 0;
    _indexWriteCursor  = 0;
  }

  /// Advance to the next buffer slot and reset write cursors.
  /// Call once per frame after all [drawVertices] calls have been submitted.
  void rotate() {
    _current = (_current + 1) % depth;
    resetCursors();
  }
}
