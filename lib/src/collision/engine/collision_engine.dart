import 'dart:math' as math;
import 'dart:typed_data';
import 'package:goo2d/src/collision/worker/collision_delta.dart';
import 'package:goo2d/src/physics/worker/data/collider_shape_type.dart';

/// Pure-Dart trigger-only collision engine.
///
/// All hot-path state lives in flat typed arrays — zero Map/Set/List usage
/// in [step]. Handles are allocated by the caller and passed to [createShape].
///
/// Broad phase: spatial hash grid (counting sort, auto-tuned cell size).
/// Narrow phase: per-shape-pair exact tests (SAT, circle-circle, etc.).
/// Delta detection: two swapped pair hash tables — O(N) enter/stay/exit.
class CollisionEngine {
  static const _initCap = 64;
  static const _initPairCap = 128;
  static const _initGridCap = 512;

  int _cap = _initCap;
  int _count = 0;

  // ── Slot arrays (parallel, indexed 0.._cap-1) ──────────────────────────
  late Int32List _handles; // external handle or -1 if free
  late Uint8List _shapeType; // ColliderShapeType.index
  late Uint8List _flags; // bit0 = enabled
  late Float32List _posX, _posY, _posAngle; // world transform
  late Float32List _offsetX, _offsetY; // local shape offset
  late Float32List _halfW, _halfH; // box half-extents
  late Float32List _radius; // circle radius / capsule end-cap radius
  late Float32List _capsuleHalfLen; // capsule half-length along axis
  late Uint8List _capsuleDir; // 0=horizontal, 1=vertical
  late Float32List _edgeX0, _edgeY0, _edgeX1, _edgeY1;
  late Int32List _polyStart, _polyCount; // range in _polyVerts
  late Float32List _aabbMinX, _aabbMinY, _aabbMaxX, _aabbMaxY;
  late Int32List _layer; // layer bit index (0-31)
  late Int32List _excludeLayers; // exclusion bitmask

  // ── Polygon vertex buffer (grows monotonically; no compaction) ──────────
  Float32List _polyVerts = Float32List(512);
  int _polyVertCount = 0;

  // ── Handle→slot open-addressing hash table ──────────────────────────────
  late Int32List _handleMap; // value = slot index; -1 = empty, -2 = tombstone
  int _handleMapCap = _initCap * 4;
  int _handleMapMask = _initCap * 4 - 1;

  // ── Free-slot stack ─────────────────────────────────────────────────────
  late Int32List _freeSlots;
  int _freeTop = 0;

  // ── Pair hash tables (two tables, pointer-swapped each step) ────────────
  late Int32List _prevPairA, _prevPairB;
  late Int32List _currPairA, _currPairB;
  int _pairCap = _initPairCap;
  int _pairMask = _initPairCap - 1;
  int _currPairCount = 0;

  // ── Layer collision matrix ───────────────────────────────────────────────
  final Int32List _layerMask = Int32List(32)..fillRange(0, 32, ~0);

  // ── Spatial hash grid (counting sort) ───────────────────────────────────
  final Int32List _gridCount = Int32List(_initGridCap);
  final Int32List _gridStart = Int32List(_initGridCap);
  Int32List _gridBodies = Int32List(_initGridCap * 4);
  static const int _gridCap = _initGridCap;
  static const int _gridMask = _initGridCap - 1;
  double _cellSize = 1.0;

  // ── Delta output scratch buffers (grown on demand, reused each step) ─────
  Int32List _enterBuf = Int32List(64);
  Int32List _stayBuf = Int32List(64);
  Int32List _exitBuf = Int32List(64);
  int _enterCount = 0, _stayCount = 0, _exitCount = 0;

  CollisionEngine() {
    _allocSlots(_initCap);
    _handleMap = Int32List(_handleMapCap)..fillRange(0, _handleMapCap, -1);
    _freeSlots = Int32List(_initCap);
    for (var i = 0; i < _initCap; i++) {
      _freeSlots[i] = i;
    }
    _freeTop = _initCap;
    _prevPairA = Int32List(_initPairCap)..fillRange(0, _initPairCap, -1);
    _prevPairB = Int32List(_initPairCap)..fillRange(0, _initPairCap, -1);
    _currPairA = Int32List(_initPairCap)..fillRange(0, _initPairCap, -1);
    _currPairB = Int32List(_initPairCap)..fillRange(0, _initPairCap, -1);
  }

  void _allocSlots(int cap) {
    _handles = Int32List(cap)..fillRange(0, cap, -1);
    _shapeType = Uint8List(cap);
    _flags = Uint8List(cap);
    _posX = Float32List(cap);
    _posY = Float32List(cap);
    _posAngle = Float32List(cap);
    _offsetX = Float32List(cap);
    _offsetY = Float32List(cap);
    _halfW = Float32List(cap);
    _halfH = Float32List(cap);
    _radius = Float32List(cap);
    _capsuleHalfLen = Float32List(cap);
    _capsuleDir = Uint8List(cap);
    _edgeX0 = Float32List(cap);
    _edgeY0 = Float32List(cap);
    _edgeX1 = Float32List(cap);
    _edgeY1 = Float32List(cap);
    _polyStart = Int32List(cap)..fillRange(0, cap, -1);
    _polyCount = Int32List(cap);
    _aabbMinX = Float32List(cap);
    _aabbMinY = Float32List(cap);
    _aabbMaxX = Float32List(cap);
    _aabbMaxY = Float32List(cap);
    _layer = Int32List(cap);
    _excludeLayers = Int32List(cap);
  }

  // ── Handle↔slot hash table ───────────────────────────────────────────────

  int _hmHash(int h) => (h * 0x9E3779B9) & _handleMapMask;

  int _slotFor(int handle) {
    var bucket = _hmHash(handle);
    while (true) {
      final s = _handleMap[bucket];
      if (s == -1) return -1;
      if (s != -2 && _handles[s] == handle) return s;
      bucket = (bucket + 1) & _handleMapMask;
    }
  }

  void _hmInsert(int handle, int slot) {
    var bucket = _hmHash(handle);
    while (true) {
      final s = _handleMap[bucket];
      if (s == -1 || s == -2) {
        _handleMap[bucket] = slot;
        return;
      }
      bucket = (bucket + 1) & _handleMapMask;
    }
  }

  void _hmRemove(int handle) {
    var bucket = _hmHash(handle);
    while (true) {
      final s = _handleMap[bucket];
      if (s == -1) return;
      if (s != -2 && _handles[s] == handle) {
        _handleMap[bucket] = -2; // tombstone
        return;
      }
      bucket = (bucket + 1) & _handleMapMask;
    }
  }

  void _rebuildHandleMap(int newCap) {
    _handleMapCap = newCap;
    _handleMapMask = newCap - 1;
    _handleMap = Int32List(newCap)..fillRange(0, newCap, -1);
    for (var i = 0; i < _cap; i++) {
      if (_handles[i] != -1) _hmInsert(_handles[i], i);
    }
  }

  // ── Pair hash table ───────────────────────────────────────────────────────

  int _pairHash(int a, int b) =>
      ((a * 0x9E3779B9) ^ (b * 0x6C62272E)) & _pairMask;

  bool _inTable(Int32List pa, Int32List pb, int a, int b) {
    var bucket = _pairHash(a, b);
    while (true) {
      final ea = pa[bucket];
      if (ea == -1) return false;
      if (ea == a && pb[bucket] == b) return true;
      bucket = (bucket + 1) & _pairMask;
    }
  }

  void _insertCurrPair(int a, int b) {
    if (_inTable(_currPairA, _currPairB, a, b)) return;
    if (_currPairCount >= _pairCap ~/ 2) _growPairTables();
    var bucket = _pairHash(a, b);
    while (_currPairA[bucket] != -1) {
      bucket = (bucket + 1) & _pairMask;
    }
    _currPairA[bucket] = a;
    _currPairB[bucket] = b;
    _currPairCount++;
  }

  void _growPairTables() {
    final newCap = _pairCap * 2;
    final newMask = newCap - 1;
    final newCA = Int32List(newCap)..fillRange(0, newCap, -1);
    final newCB = Int32List(newCap)..fillRange(0, newCap, -1);
    final newPA = Int32List(newCap)..fillRange(0, newCap, -1);
    final newPB = Int32List(newCap)..fillRange(0, newCap, -1);

    void rehash(Int32List srcA, Int32List srcB, Int32List dstA, Int32List dstB) {
      for (var i = 0; i < _pairCap; i++) {
        final a = srcA[i];
        if (a == -1) continue;
        final b = srcB[i];
        var bucket = ((a * 0x9E3779B9) ^ (b * 0x6C62272E)) & newMask;
        while (dstA[bucket] != -1) {
          bucket = (bucket + 1) & newMask;
        }
        dstA[bucket] = a;
        dstB[bucket] = b;
      }
    }

    rehash(_currPairA, _currPairB, newCA, newCB);
    rehash(_prevPairA, _prevPairB, newPA, newPB);
    _pairCap = newCap;
    _pairMask = newMask;
    _currPairA = newCA;
    _currPairB = newCB;
    _prevPairA = newPA;
    _prevPairB = newPB;
  }

  // ── Shape lifecycle ───────────────────────────────────────────────────────

  void createShape(int handle, ColliderShapeType type) {
    if (_freeTop == 0) _grow();
    final slot = _freeSlots[--_freeTop];
    _handles[slot] = handle;
    _shapeType[slot] = type.index;
    _flags[slot] = 1;
    _posX[slot] = _posY[slot] = _posAngle[slot] = 0;
    _offsetX[slot] = _offsetY[slot] = 0;
    _halfW[slot] = _halfH[slot] = 0.5;
    _radius[slot] = 0.5;
    _capsuleHalfLen[slot] = 0.5;
    _capsuleDir[slot] = 0;
    _edgeX0[slot] = _edgeY0[slot] = 0;
    _edgeX1[slot] = 1;
    _edgeY1[slot] = 0;
    _polyStart[slot] = -1;
    _polyCount[slot] = 0;
    _layer[slot] = 0;
    _excludeLayers[slot] = 0;
    _hmInsert(handle, slot);
    _count++;
  }

  void destroyShape(int handle) {
    final slot = _slotFor(handle);
    if (slot < 0) return;
    _hmRemove(handle);
    _handles[slot] = -1;
    if (_freeTop >= _freeSlots.length) {
      final nf = Int32List(_freeSlots.length * 2);
      nf.setRange(0, _freeTop, _freeSlots);
      _freeSlots = nf;
    }
    _freeSlots[_freeTop++] = slot;
    _count--;
  }

  void setTransform(int handle, double x, double y, double angle) {
    final s = _slotFor(handle);
    if (s < 0) return;
    _posX[s] = x;
    _posY[s] = y;
    _posAngle[s] = angle;
  }

  void setEnabled(int handle, bool enabled) {
    final s = _slotFor(handle);
    if (s < 0) return;
    _flags[s] = (_flags[s] & ~1) | (enabled ? 1 : 0);
  }

  void setLayer(int handle, int layer) {
    final s = _slotFor(handle);
    if (s < 0) return;
    _layer[s] = layer & 31;
  }

  void setExcludeLayers(int handle, int mask) {
    final s = _slotFor(handle);
    if (s < 0) return;
    _excludeLayers[s] = mask;
  }

  void setOffset(int handle, double ox, double oy) {
    final s = _slotFor(handle);
    if (s < 0) return;
    _offsetX[s] = ox;
    _offsetY[s] = oy;
  }

  void setBox(int handle, double halfW, double halfH) {
    final s = _slotFor(handle);
    if (s < 0) return;
    _halfW[s] = halfW;
    _halfH[s] = halfH;
  }

  void setCircle(int handle, double radius) {
    final s = _slotFor(handle);
    if (s < 0) return;
    _radius[s] = radius;
  }

  void setCapsule(int handle, double halfLen, double radius, int dir) {
    final s = _slotFor(handle);
    if (s < 0) return;
    _capsuleHalfLen[s] = halfLen;
    _radius[s] = radius;
    _capsuleDir[s] = dir & 1;
  }

  void setPolygon(int handle, Float32List vertices) {
    final s = _slotFor(handle);
    if (s < 0) return;
    final vcount = vertices.length;
    while (_polyVertCount + vcount > _polyVerts.length) {
      final nv = Float32List(_polyVerts.length * 2);
      nv.setRange(0, _polyVertCount, _polyVerts);
      _polyVerts = nv;
    }
    _polyStart[s] = _polyVertCount;
    _polyCount[s] = vcount ~/ 2;
    for (var i = 0; i < vcount; i++) {
      _polyVerts[_polyVertCount + i] = vertices[i];
    }
    _polyVertCount += vcount;
  }

  void setEdge(int handle, double x0, double y0, double x1, double y1) {
    final s = _slotFor(handle);
    if (s < 0) return;
    _edgeX0[s] = x0;
    _edgeY0[s] = y0;
    _edgeX1[s] = x1;
    _edgeY1[s] = y1;
  }

  void setLayerMask(int layer, int mask) {
    _layerMask[layer & 31] = mask;
  }

  void setIgnoreLayerCollision(int layer1, int layer2, bool ignore) {
    final l1 = layer1 & 31, l2 = layer2 & 31;
    if (ignore) {
      _layerMask[l1] &= ~(1 << l2);
      _layerMask[l2] &= ~(1 << l1);
    } else {
      _layerMask[l1] |= (1 << l2);
      _layerMask[l2] |= (1 << l1);
    }
  }

  // ── Capacity growth ───────────────────────────────────────────────────────

  void _grow() {
    final oldCap = _cap;
    final newCap = _cap * 2;

    Float32List gf(Float32List src) {
      final n = Float32List(newCap);
      n.setRange(0, oldCap, src);
      return n;
    }

    Uint8List gu(Uint8List src) {
      final n = Uint8List(newCap);
      n.setRange(0, oldCap, src);
      return n;
    }

    Int32List gi(Int32List src, [int fill = 0]) {
      final n = Int32List(newCap);
      if (fill != 0) n.fillRange(0, newCap, fill);
      n.setRange(0, oldCap, src);
      return n;
    }

    final newHandles = Int32List(newCap)..fillRange(0, newCap, -1);
    newHandles.setRange(0, oldCap, _handles);
    _handles = newHandles;
    _shapeType = gu(_shapeType);
    _flags = gu(_flags);
    _capsuleDir = gu(_capsuleDir);
    _posX = gf(_posX);
    _posY = gf(_posY);
    _posAngle = gf(_posAngle);
    _offsetX = gf(_offsetX);
    _offsetY = gf(_offsetY);
    _halfW = gf(_halfW);
    _halfH = gf(_halfH);
    _radius = gf(_radius);
    _capsuleHalfLen = gf(_capsuleHalfLen);
    _edgeX0 = gf(_edgeX0);
    _edgeY0 = gf(_edgeY0);
    _edgeX1 = gf(_edgeX1);
    _edgeY1 = gf(_edgeY1);
    _aabbMinX = gf(_aabbMinX);
    _aabbMinY = gf(_aabbMinY);
    _aabbMaxX = gf(_aabbMaxX);
    _aabbMaxY = gf(_aabbMaxY);
    _polyStart = gi(_polyStart, -1);
    _polyCount = gi(_polyCount);
    _layer = gi(_layer);
    _excludeLayers = gi(_excludeLayers);

    // Push new free slots
    final needed = _freeTop + (newCap - oldCap);
    if (needed > _freeSlots.length) {
      final nf = Int32List(needed * 2);
      nf.setRange(0, _freeTop, _freeSlots);
      _freeSlots = nf;
    }
    for (var i = oldCap; i < newCap; i++) {
      _freeSlots[_freeTop++] = i;
    }

    if (_count >= _handleMapCap * 3 ~/ 4) {
      _rebuildHandleMap(_handleMapCap * 2);
    }

    _cap = newCap;
  }

  // ── AABB computation ──────────────────────────────────────────────────────

  void _computeAabbs() {
    for (var i = 0; i < _cap; i++) {
      if (_handles[i] == -1 || (_flags[i] & 1) == 0) continue;
      _computeAabb(i);
    }
  }

  void _computeAabb(int s) {
    final cx = _posX[s] + _offsetX[s];
    final cy = _posY[s] + _offsetY[s];
    final angle = _posAngle[s];

    switch (ColliderShapeType.values[_shapeType[s]]) {
      case ColliderShapeType.circle:
        final r = _radius[s];
        _aabbMinX[s] = cx - r;
        _aabbMinY[s] = cy - r;
        _aabbMaxX[s] = cx + r;
        _aabbMaxY[s] = cy + r;

      case ColliderShapeType.box:
        final hw = _halfW[s], hh = _halfH[s];
        final cosA = math.cos(angle).abs(), sinA = math.sin(angle).abs();
        final ex = hw * cosA + hh * sinA;
        final ey = hw * sinA + hh * cosA;
        _aabbMinX[s] = cx - ex;
        _aabbMinY[s] = cy - ey;
        _aabbMaxX[s] = cx + ex;
        _aabbMaxY[s] = cy + ey;

      case ColliderShapeType.capsule:
        final hl = _capsuleHalfLen[s], r = _radius[s];
        final axisAngle =
            _capsuleDir[s] == 0 ? angle : angle + math.pi / 2;
        final ax = hl * math.cos(axisAngle);
        final ay = hl * math.sin(axisAngle);
        _aabbMinX[s] = cx - ax.abs() - r;
        _aabbMinY[s] = cy - ay.abs() - r;
        _aabbMaxX[s] = cx + ax.abs() + r;
        _aabbMaxY[s] = cy + ay.abs() + r;

      case ColliderShapeType.edge:
        final x0 = _posX[s] + _edgeX0[s], y0 = _posY[s] + _edgeY0[s];
        final x1 = _posX[s] + _edgeX1[s], y1 = _posY[s] + _edgeY1[s];
        _aabbMinX[s] = math.min(x0, x1) - 0.01;
        _aabbMinY[s] = math.min(y0, y1) - 0.01;
        _aabbMaxX[s] = math.max(x0, x1) + 0.01;
        _aabbMaxY[s] = math.max(y0, y1) + 0.01;

      case ColliderShapeType.polygon:
        final start = _polyStart[s], count = _polyCount[s];
        if (count == 0) {
          _aabbMinX[s] = _aabbMinY[s] = _aabbMaxX[s] = _aabbMaxY[s] = cx;
          return;
        }
        final cosA = math.cos(angle), sinA = math.sin(angle);
        var minX = double.infinity, minY = double.infinity;
        var maxX = -double.infinity, maxY = -double.infinity;
        for (var vi = 0; vi < count; vi++) {
          final lx = _polyVerts[start + vi * 2];
          final ly = _polyVerts[start + vi * 2 + 1];
          final wx = cx + lx * cosA - ly * sinA;
          final wy = cy + lx * sinA + ly * cosA;
          if (wx < minX) minX = wx;
          if (wy < minY) minY = wy;
          if (wx > maxX) maxX = wx;
          if (wy > maxY) maxY = wy;
        }
        _aabbMinX[s] = minX;
        _aabbMinY[s] = minY;
        _aabbMaxX[s] = maxX;
        _aabbMaxY[s] = maxY;

      case ColliderShapeType.composite:
        _aabbMinX[s] = cx - 1;
        _aabbMinY[s] = cy - 1;
        _aabbMaxX[s] = cx + 1;
        _aabbMaxY[s] = cy + 1;
    }
  }

  // ── Broad phase: spatial hash grid ────────────────────────────────────────

  int _cellHash(int cx, int cy) =>
      (cx * 73856093 ^ cy * 19349663) & _gridMask;

  void _broadPhase() {
    double sumDiag = 0.0;
    int activeCount = 0;
    for (var i = 0; i < _cap; i++) {
      if (_handles[i] == -1 || (_flags[i] & 1) == 0) continue;
      final dx = _aabbMaxX[i] - _aabbMinX[i];
      final dy = _aabbMaxY[i] - _aabbMinY[i];
      sumDiag += math.sqrt(dx * dx + dy * dy);
      activeCount++;
    }
    if (activeCount == 0) return;
    _cellSize = math.max(sumDiag / activeCount * 2.0, 0.01);

    _gridCount.fillRange(0, _gridCap, 0);

    // Count insertions per bucket
    for (var i = 0; i < _cap; i++) {
      if (_handles[i] == -1 || (_flags[i] & 1) == 0) continue;
      final cMinX = (_aabbMinX[i] / _cellSize).floor();
      final cMinY = (_aabbMinY[i] / _cellSize).floor();
      final cMaxX = (_aabbMaxX[i] / _cellSize).floor();
      final cMaxY = (_aabbMaxY[i] / _cellSize).floor();
      for (var cy = cMinY; cy <= cMaxY; cy++) {
        for (var cx = cMinX; cx <= cMaxX; cx++) {
          _gridCount[_cellHash(cx, cy)]++;
        }
      }
    }

    // Prefix sum
    var total = 0;
    for (var i = 0; i < _gridCap; i++) {
      _gridStart[i] = total;
      total += _gridCount[i];
      _gridCount[i] = 0;
    }

    if (total > _gridBodies.length) {
      _gridBodies = Int32List(total * 2);
    }

    // Fill pass
    for (var i = 0; i < _cap; i++) {
      if (_handles[i] == -1 || (_flags[i] & 1) == 0) continue;
      final cMinX = (_aabbMinX[i] / _cellSize).floor();
      final cMinY = (_aabbMinY[i] / _cellSize).floor();
      final cMaxX = (_aabbMaxX[i] / _cellSize).floor();
      final cMaxY = (_aabbMaxY[i] / _cellSize).floor();
      for (var cy = cMinY; cy <= cMaxY; cy++) {
        for (var cx = cMinX; cx <= cMaxX; cx++) {
          final bucket = _cellHash(cx, cy);
          _gridBodies[_gridStart[bucket] + _gridCount[bucket]] = i;
          _gridCount[bucket]++;
        }
      }
    }

    // Emit confirmed pairs
    for (var bucket = 0; bucket < _gridCap; bucket++) {
      final start = _gridStart[bucket];
      final cnt = _gridCount[bucket];
      if (cnt < 2) continue;
      for (var ai = 0; ai < cnt; ai++) {
        final sA = _gridBodies[start + ai];
        for (var bi = ai + 1; bi < cnt; bi++) {
          final sB = _gridBodies[start + bi];
          if (!_aabbOverlap(sA, sB)) continue;
          if (!_layerCanCollide(sA, sB)) continue;
          if (!_narrowPhase(sA, sB)) continue;
          final hA = _handles[sA], hB = _handles[sB];
          final a = hA < hB ? hA : hB;
          final b = hA < hB ? hB : hA;
          _insertCurrPair(a, b);
        }
      }
    }
  }

  bool _aabbOverlap(int sA, int sB) =>
      _aabbMaxX[sA] >= _aabbMinX[sB] &&
      _aabbMinX[sA] <= _aabbMaxX[sB] &&
      _aabbMaxY[sA] >= _aabbMinY[sB] &&
      _aabbMinY[sA] <= _aabbMaxY[sB];

  bool _layerCanCollide(int sA, int sB) {
    final la = _layer[sA], lb = _layer[sB];
    if ((_excludeLayers[sA] & (1 << lb)) != 0) return false;
    if ((_excludeLayers[sB] & (1 << la)) != 0) return false;
    if ((_layerMask[la] & (1 << lb)) == 0) return false;
    return true;
  }

  // ── Narrow phase ──────────────────────────────────────────────────────────

  bool _narrowPhase(int sA, int sB) {
    final tA = ColliderShapeType.values[_shapeType[sA]];
    final tB = ColliderShapeType.values[_shapeType[sB]];
    return tA.index <= tB.index
        ? _npOrdered(sA, tA, sB, tB)
        : _npOrdered(sB, tB, sA, tA);
  }

  bool _npOrdered(
      int sA, ColliderShapeType tA, int sB, ColliderShapeType tB) {
    switch (tA) {
      case ColliderShapeType.box:
        switch (tB) {
          case ColliderShapeType.box:
            return _boxBox(sA, sB);
          case ColliderShapeType.circle:
            return _boxCircle(sA, sB);
          case ColliderShapeType.capsule:
            return _boxCapsule(sA, sB);
          case ColliderShapeType.polygon:
            return _boxPolygon(sA, sB);
          case ColliderShapeType.edge:
            return _boxEdge(sA, sB);
          default:
            return true;
        }
      case ColliderShapeType.circle:
        switch (tB) {
          case ColliderShapeType.circle:
            return _circleCircle(sA, sB);
          case ColliderShapeType.capsule:
            return _circleCapsule(sA, sB);
          case ColliderShapeType.polygon:
            return _circlePolygon(sA, sB);
          case ColliderShapeType.edge:
            return _circleEdge(sA, sB);
          default:
            return true;
        }
      case ColliderShapeType.capsule:
        switch (tB) {
          case ColliderShapeType.capsule:
            return _capsuleCapsule(sA, sB);
          case ColliderShapeType.edge:
            return _capsuleEdge(sA, sB);
          default:
            return true;
        }
      case ColliderShapeType.polygon:
        switch (tB) {
          case ColliderShapeType.polygon:
            return _polyPoly(sA, sB);
          default:
            return true;
        }
      default:
        return true;
    }
  }

  // Circle-Circle
  bool _circleCircle(int sA, int sB) {
    final dx = (_posX[sA] + _offsetX[sA]) - (_posX[sB] + _offsetX[sB]);
    final dy = (_posY[sA] + _offsetY[sA]) - (_posY[sB] + _offsetY[sB]);
    final sumR = _radius[sA] + _radius[sB];
    return dx * dx + dy * dy <= sumR * sumR;
  }

  // Box-Box SAT (4 axes)
  bool _boxBox(int sA, int sB) {
    final cxA = _posX[sA] + _offsetX[sA];
    final cyA = _posY[sA] + _offsetY[sA];
    final hwA = _halfW[sA], hhA = _halfH[sA];
    final angA = _posAngle[sA];
    final cosA = math.cos(angA), sinA = math.sin(angA);

    final cxB = _posX[sB] + _offsetX[sB];
    final cyB = _posY[sB] + _offsetY[sB];
    final hwB = _halfW[sB], hhB = _halfH[sB];
    final angB = _posAngle[sB];
    final cosB = math.cos(angB), sinB = math.sin(angB);

    final dX = cxB - cxA, dY = cyB - cyA;

    double projOBB(
        double hw, double hh, double c, double s, double nx, double ny) {
      return hw * (c * nx + s * ny).abs() + hh * (-s * nx + c * ny).abs();
    }

    // Axis: A local-X
    var sep = (dX * cosA + dY * sinA).abs();
    if (sep > projOBB(hwA, hhA, cosA, sinA, cosA, sinA) +
        projOBB(hwB, hhB, cosB, sinB, cosA, sinA)) { return false; }

    // Axis: A local-Y
    sep = (-dX * sinA + dY * cosA).abs();
    if (sep > projOBB(hwA, hhA, cosA, sinA, -sinA, cosA) +
        projOBB(hwB, hhB, cosB, sinB, -sinA, cosA)) { return false; }

    // Axis: B local-X
    sep = (dX * cosB + dY * sinB).abs();
    if (sep > projOBB(hwA, hhA, cosA, sinA, cosB, sinB) +
        projOBB(hwB, hhB, cosB, sinB, cosB, sinB)) { return false; }

    // Axis: B local-Y
    sep = (-dX * sinB + dY * cosB).abs();
    if (sep > projOBB(hwA, hhA, cosA, sinA, -sinB, cosB) +
        projOBB(hwB, hhB, cosB, sinB, -sinB, cosB)) { return false; }

    return true;
  }

  // Box-Circle (closest point on OBB)
  bool _boxCircle(int sBox, int sCircle) {
    final cxBox = _posX[sBox] + _offsetX[sBox];
    final cyBox = _posY[sBox] + _offsetY[sBox];
    final hw = _halfW[sBox], hh = _halfH[sBox];
    final ang = _posAngle[sBox];
    final cxC = _posX[sCircle] + _offsetX[sCircle];
    final cyC = _posY[sCircle] + _offsetY[sCircle];
    final r = _radius[sCircle];

    // Transform circle center to box local space (inverse rotate)
    final dx = cxC - cxBox, dy = cyC - cyBox;
    final cosInv = math.cos(-ang), sinInv = math.sin(-ang);
    final lx = dx * cosInv - dy * sinInv;
    final ly = dx * sinInv + dy * cosInv;

    // Closest point on box to circle center
    final cx2 = lx.clamp(-hw, hw);
    final cy2 = ly.clamp(-hh, hh);
    final ex = lx - cx2, ey = ly - cy2;
    return ex * ex + ey * ey <= r * r;
  }

  // Box-Capsule (treat capsule as a moving circle along its axis)
  bool _boxCapsule(int sBox, int sCap) {
    final cxBox = _posX[sBox] + _offsetX[sBox];
    final cyBox = _posY[sBox] + _offsetY[sBox];
    final hw = _halfW[sBox], hh = _halfH[sBox];
    final angBox = _posAngle[sBox];

    final (double ax, double ay, double bx, double by) =
        _capsuleEndpoints(sCap);
    final r = _radius[sCap];

    // Find closest point on capsule axis to box center
    final t = _segmentParam(cxBox, cyBox, ax, ay, bx, by);
    final px = ax + t * (bx - ax), py = ay + t * (by - ay);

    // Box-circle test with that closest point
    final dx = px - cxBox, dy = py - cyBox;
    final cosInv = math.cos(-angBox), sinInv = math.sin(-angBox);
    final lx = dx * cosInv - dy * sinInv;
    final ly = dx * sinInv + dy * cosInv;
    final cx2 = lx.clamp(-hw, hw), cy2 = ly.clamp(-hh, hh);
    final ex = lx - cx2, ey = ly - cy2;
    return ex * ex + ey * ey <= r * r;
  }

  // Box-Polygon (SAT: 2 box axes + polygon edge normals)
  bool _boxPolygon(int sBox, int sPoly) {
    final cxBox = _posX[sBox] + _offsetX[sBox];
    final cyBox = _posY[sBox] + _offsetY[sBox];
    final hw = _halfW[sBox], hh = _halfH[sBox];
    final angBox = _posAngle[sBox];
    final cosBox = math.cos(angBox), sinBox = math.sin(angBox);

    final cxPoly = _posX[sPoly] + _offsetX[sPoly];
    final cyPoly = _posY[sPoly] + _offsetY[sPoly];
    final angPoly = _posAngle[sPoly];
    final cosPoly = math.cos(angPoly), sinPoly = math.sin(angPoly);
    final start = _polyStart[sPoly], count = _polyCount[sPoly];

    if (count == 0) return false;

    // Project polygon vertices to world space once (stack-allocated via loop)
    // Test box axes
    for (var axisIdx = 0; axisIdx < 2; axisIdx++) {
      final nx = axisIdx == 0 ? cosBox : -sinBox;
      final ny = axisIdx == 0 ? sinBox : cosBox;
      // Box projection on its own axis
      final boxProj = cxBox * nx + cyBox * ny;
      final boxR = hw * (cosBox * nx + sinBox * ny).abs() +
          hh * (-sinBox * nx + cosBox * ny).abs();

      var polyMin = double.infinity, polyMax = -double.infinity;
      for (var vi = 0; vi < count; vi++) {
        final lx = _polyVerts[start + vi * 2];
        final ly = _polyVerts[start + vi * 2 + 1];
        final wx = cxPoly + lx * cosPoly - ly * sinPoly;
        final wy = cyPoly + lx * sinPoly + ly * cosPoly;
        final proj = wx * nx + wy * ny;
        if (proj < polyMin) polyMin = proj;
        if (proj > polyMax) polyMax = proj;
      }

      if (boxProj - boxR > polyMax || polyMin > boxProj + boxR) return false;
    }

    // Test polygon edge normals
    for (var vi = 0; vi < count; vi++) {
      final lx0 = _polyVerts[start + vi * 2];
      final ly0 = _polyVerts[start + vi * 2 + 1];
      final lx1 = _polyVerts[start + ((vi + 1) % count) * 2];
      final ly1 = _polyVerts[start + ((vi + 1) % count) * 2 + 1];

      // Edge normal in world space
      final ex = lx1 - lx0, ey = ly1 - ly0;
      final nx = -(ey * cosPoly - ex * sinPoly);
      final ny = -(ex * cosPoly + ey * sinPoly);
      // Normalise skip for SAT (magnitude factors out)
      // Actually for SAT we need to normalise to compare correctly
      final len = math.sqrt(nx * nx + ny * ny);
      if (len < 1e-10) continue;
      final nnx = nx / len, nny = ny / len;

      // Box projection
      final boxProj = cxBox * nnx + cyBox * nny;
      final boxR = hw * (cosBox * nnx + sinBox * nny).abs() +
          hh * (-sinBox * nnx + cosBox * nny).abs();

      // Polygon projection
      var polyMin = double.infinity, polyMax = -double.infinity;
      for (var vj = 0; vj < count; vj++) {
        final lx = _polyVerts[start + vj * 2];
        final ly = _polyVerts[start + vj * 2 + 1];
        final wx = cxPoly + lx * cosPoly - ly * sinPoly;
        final wy = cyPoly + lx * sinPoly + ly * cosPoly;
        final proj = wx * nnx + wy * nny;
        if (proj < polyMin) polyMin = proj;
        if (proj > polyMax) polyMax = proj;
      }

      if (boxProj - boxR > polyMax || polyMin > boxProj + boxR) return false;
    }

    return true;
  }

  // Box-Edge
  bool _boxEdge(int sBox, int sEdge) {
    final cxBox = _posX[sBox] + _offsetX[sBox];
    final cyBox = _posY[sBox] + _offsetY[sBox];
    final hw = _halfW[sBox], hh = _halfH[sBox];
    final ang = _posAngle[sBox];
    final ex0 = _posX[sEdge] + _edgeX0[sEdge];
    final ey0 = _posY[sEdge] + _edgeY0[sEdge];
    final ex1 = _posX[sEdge] + _edgeX1[sEdge];
    final ey1 = _posY[sEdge] + _edgeY1[sEdge];

    // Transform edge to box local space
    final cosInv = math.cos(-ang), sinInv = math.sin(-ang);
    final d0x = ex0 - cxBox, d0y = ey0 - cyBox;
    final l0x = d0x * cosInv - d0y * sinInv;
    final l0y = d0x * sinInv + d0y * cosInv;
    final d1x = ex1 - cxBox, d1y = ey1 - cyBox;
    final l1x = d1x * cosInv - d1y * sinInv;
    final l1y = d1x * sinInv + d1y * cosInv;

    return _segmentAabbTest(l0x, l0y, l1x, l1y, hw, hh);
  }

  bool _segmentAabbTest(
      double ax, double ay, double bx, double by, double hw, double hh) {
    var tMin = 0.0, tMax = 1.0;
    final dxs = [bx - ax, by - ay];
    final mins = [-hw, -hh];
    final maxs = [hw, hh];
    final origins = [ax, ay];
    for (var axis = 0; axis < 2; axis++) {
      final d = dxs[axis];
      if (d.abs() < 1e-10) {
        if (origins[axis] < mins[axis] || origins[axis] > maxs[axis]) {
          return false;
        }
      } else {
        var t1 = (mins[axis] - origins[axis]) / d;
        var t2 = (maxs[axis] - origins[axis]) / d;
        if (t1 > t2) {
          final tmp = t1;
          t1 = t2;
          t2 = tmp;
        }
        tMin = math.max(tMin, t1);
        tMax = math.min(tMax, t2);
        if (tMin > tMax) return false;
      }
    }
    return true;
  }

  // Circle-Edge
  bool _circleEdge(int sCircle, int sEdge) {
    final cx = _posX[sCircle] + _offsetX[sCircle];
    final cy = _posY[sCircle] + _offsetY[sCircle];
    final r = _radius[sCircle];
    final x0 = _posX[sEdge] + _edgeX0[sEdge];
    final y0 = _posY[sEdge] + _edgeY0[sEdge];
    final x1 = _posX[sEdge] + _edgeX1[sEdge];
    final y1 = _posY[sEdge] + _edgeY1[sEdge];
    return _ptSegDist2(cx, cy, x0, y0, x1, y1) <= r * r;
  }

  // Circle-Capsule
  bool _circleCapsule(int sCircle, int sCap) {
    final cx = _posX[sCircle] + _offsetX[sCircle];
    final cy = _posY[sCircle] + _offsetY[sCircle];
    final rC = _radius[sCircle];
    final (double ax, double ay, double bx, double by) =
        _capsuleEndpoints(sCap);
    final sumR = rC + _radius[sCap];
    return _ptSegDist2(cx, cy, ax, ay, bx, by) <= sumR * sumR;
  }

  // Circle-Polygon
  bool _circlePolygon(int sCircle, int sPoly) {
    final cx = _posX[sCircle] + _offsetX[sCircle];
    final cy = _posY[sCircle] + _offsetY[sCircle];
    final r = _radius[sCircle];
    final pcx = _posX[sPoly] + _offsetX[sPoly];
    final pcy = _posY[sPoly] + _offsetY[sPoly];
    final ang = _posAngle[sPoly];
    final cosA = math.cos(ang), sinA = math.sin(ang);
    final start = _polyStart[sPoly], count = _polyCount[sPoly];
    if (count == 0) return false;

    // Check distance from circle to each polygon edge
    for (var vi = 0; vi < count; vi++) {
      final lx0 = _polyVerts[start + vi * 2];
      final ly0 = _polyVerts[start + vi * 2 + 1];
      final lx1 = _polyVerts[start + ((vi + 1) % count) * 2];
      final ly1 = _polyVerts[start + ((vi + 1) % count) * 2 + 1];
      final wx0 = pcx + lx0 * cosA - ly0 * sinA;
      final wy0 = pcy + lx0 * sinA + ly0 * cosA;
      final wx1 = pcx + lx1 * cosA - ly1 * sinA;
      final wy1 = pcy + lx1 * sinA + ly1 * cosA;
      if (_ptSegDist2(cx, cy, wx0, wy0, wx1, wy1) <= r * r) return true;
    }
    // Check if circle center is inside polygon
    return _pointInPoly(cx, cy, start, count, pcx, pcy, cosA, sinA);
  }

  // Capsule-Capsule (segment-segment distance < sum of radii)
  bool _capsuleCapsule(int sA, int sB) {
    final (double axA, double ayA, double bxA, double byA) =
        _capsuleEndpoints(sA);
    final (double axB, double ayB, double bxB, double byB) =
        _capsuleEndpoints(sB);
    final sumR = _radius[sA] + _radius[sB];
    return _segSegDist2(axA, ayA, bxA, byA, axB, ayB, bxB, byB) <=
        sumR * sumR;
  }

  // Capsule-Edge
  bool _capsuleEdge(int sCap, int sEdge) {
    final (double ax, double ay, double bx, double by) =
        _capsuleEndpoints(sCap);
    final r = _radius[sCap];
    final x0 = _posX[sEdge] + _edgeX0[sEdge];
    final y0 = _posY[sEdge] + _edgeY0[sEdge];
    final x1 = _posX[sEdge] + _edgeX1[sEdge];
    final y1 = _posY[sEdge] + _edgeY1[sEdge];
    return _segSegDist2(ax, ay, bx, by, x0, y0, x1, y1) <= r * r;
  }

  // Polygon-Polygon SAT
  bool _polyPoly(int sA, int sB) {
    final cxA = _posX[sA] + _offsetX[sA];
    final cyA = _posY[sA] + _offsetY[sA];
    final angA = _posAngle[sA];
    final cosA = math.cos(angA), sinA = math.sin(angA);
    final startA = _polyStart[sA], countA = _polyCount[sA];

    final cxB = _posX[sB] + _offsetX[sB];
    final cyB = _posY[sB] + _offsetY[sB];
    final angB = _posAngle[sB];
    final cosB = math.cos(angB), sinB = math.sin(angB);
    final startB = _polyStart[sB], countB = _polyCount[sB];

    if (countA == 0 || countB == 0) return false;

    // Test all edges of A as separating axes
    if (!_polyPolyAxis(startA, countA, cxA, cyA, cosA, sinA,
        startB, countB, cxB, cyB, cosB, sinB)) {
      return false;
    }
    // Test all edges of B as separating axes
    if (!_polyPolyAxis(startB, countB, cxB, cyB, cosB, sinB,
        startA, countA, cxA, cyA, cosA, sinA)) {
      return false;
    }
    return true;
  }

  bool _polyPolyAxis(
    int startA, int countA, double cxA, double cyA, double cosA, double sinA,
    int startB, int countB, double cxB, double cyB, double cosB, double sinB,
  ) {
    for (var vi = 0; vi < countA; vi++) {
      final lx0 = _polyVerts[startA + vi * 2];
      final ly0 = _polyVerts[startA + vi * 2 + 1];
      final lx1 = _polyVerts[startA + ((vi + 1) % countA) * 2];
      final ly1 = _polyVerts[startA + ((vi + 1) % countA) * 2 + 1];

      // Edge in world space
      final ex = (lx1 - lx0) * cosA - (ly1 - ly0) * sinA;
      final ey = (lx1 - lx0) * sinA + (ly1 - ly0) * cosA;
      // Outward normal
      final len = math.sqrt(ex * ex + ey * ey);
      if (len < 1e-10) continue;
      final nx = ey / len, ny = -ex / len;

      // Project polygon A
      var minA = double.infinity, maxA = -double.infinity;
      for (var vj = 0; vj < countA; vj++) {
        final lx = _polyVerts[startA + vj * 2];
        final ly = _polyVerts[startA + vj * 2 + 1];
        final wx = cxA + lx * cosA - ly * sinA;
        final wy = cyA + lx * sinA + ly * cosA;
        final p = wx * nx + wy * ny;
        if (p < minA) minA = p;
        if (p > maxA) maxA = p;
      }

      // Project polygon B
      var minB = double.infinity, maxB = -double.infinity;
      for (var vj = 0; vj < countB; vj++) {
        final lx = _polyVerts[startB + vj * 2];
        final ly = _polyVerts[startB + vj * 2 + 1];
        final wx = cxB + lx * cosB - ly * sinB;
        final wy = cyB + lx * sinB + ly * cosB;
        final p = wx * nx + wy * ny;
        if (p < minB) minB = p;
        if (p > maxB) maxB = p;
      }

      if (maxA < minB || maxB < minA) return false;
    }
    return true;
  }

  // ── Geometry helpers ──────────────────────────────────────────────────────

  (double, double, double, double) _capsuleEndpoints(int s) {
    final cx = _posX[s] + _offsetX[s], cy = _posY[s] + _offsetY[s];
    final hl = _capsuleHalfLen[s];
    final axisAngle =
        _capsuleDir[s] == 0 ? _posAngle[s] : _posAngle[s] + math.pi / 2;
    final ax = hl * math.cos(axisAngle), ay = hl * math.sin(axisAngle);
    return (cx - ax, cy - ay, cx + ax, cy + ay);
  }

  double _ptSegDist2(
      double px, double py, double ax, double ay, double bx, double by) {
    final abx = bx - ax, aby = by - ay;
    final apx = px - ax, apy = py - ay;
    final len2 = abx * abx + aby * aby;
    if (len2 < 1e-12) return apx * apx + apy * apy;
    final t = ((apx * abx + apy * aby) / len2).clamp(0.0, 1.0);
    final dx = apx - t * abx, dy = apy - t * aby;
    return dx * dx + dy * dy;
  }

  double _segmentParam(
      double px, double py, double ax, double ay, double bx, double by) {
    final abx = bx - ax, aby = by - ay;
    final len2 = abx * abx + aby * aby;
    if (len2 < 1e-12) return 0.0;
    return (((px - ax) * abx + (py - ay) * aby) / len2).clamp(0.0, 1.0);
  }

  double _segSegDist2(double ax, double ay, double bx, double by, double cx,
      double cy, double dx, double dy) {
    // Check intersection first
    final d1x = bx - ax, d1y = by - ay;
    final d2x = dx - cx, d2y = dy - cy;
    final cross = d1x * d2y - d1y * d2x;
    if (cross.abs() > 1e-10) {
      final tx = cx - ax, ty = cy - ay;
      final t = (tx * d2y - ty * d2x) / cross;
      final u = (tx * d1y - ty * d1x) / cross;
      if (t >= 0 && t <= 1 && u >= 0 && u <= 1) return 0.0;
    }
    // Otherwise min of 4 endpoint distances
    final d0 = _ptSegDist2(ax, ay, cx, cy, dx, dy);
    final d1 = _ptSegDist2(bx, by, cx, cy, dx, dy);
    final d2 = _ptSegDist2(cx, cy, ax, ay, bx, by);
    final d3 = _ptSegDist2(dx, dy, ax, ay, bx, by);
    return math.min(math.min(d0, d1), math.min(d2, d3));
  }

  bool _pointInPoly(double px, double py, int start, int count, double pcx,
      double pcy, double cosA, double sinA) {
    var crossings = 0;
    for (var vi = 0; vi < count; vi++) {
      final lx0 = _polyVerts[start + vi * 2];
      final ly0 = _polyVerts[start + vi * 2 + 1];
      final lx1 = _polyVerts[start + ((vi + 1) % count) * 2];
      final ly1 = _polyVerts[start + ((vi + 1) % count) * 2 + 1];
      final wy0 = pcy + lx0 * sinA + ly0 * cosA;
      final wy1 = pcy + lx1 * sinA + ly1 * cosA;
      if ((wy0 > py) != (wy1 > py)) {
        final wx0 = pcx + lx0 * cosA - ly0 * sinA;
        final wx1 = pcx + lx1 * cosA - ly1 * sinA;
        final t = (py - wy0) / (wy1 - wy0);
        if (px < wx0 + t * (wx1 - wx0)) crossings++;
      }
    }
    return (crossings & 1) == 1;
  }

  // ── Delta output helpers ──────────────────────────────────────────────────

  void _appendEnter(int a, int b) {
    if (_enterCount * 2 + 2 > _enterBuf.length) {
      final n = Int32List(_enterBuf.length * 2);
      n.setRange(0, _enterCount * 2, _enterBuf);
      _enterBuf = n;
    }
    _enterBuf[_enterCount * 2] = a;
    _enterBuf[_enterCount * 2 + 1] = b;
    _enterCount++;
  }

  void _appendStay(int a, int b) {
    if (_stayCount * 2 + 2 > _stayBuf.length) {
      final n = Int32List(_stayBuf.length * 2);
      n.setRange(0, _stayCount * 2, _stayBuf);
      _stayBuf = n;
    }
    _stayBuf[_stayCount * 2] = a;
    _stayBuf[_stayCount * 2 + 1] = b;
    _stayCount++;
  }

  void _appendExit(int a, int b) {
    if (_exitCount * 2 + 2 > _exitBuf.length) {
      final n = Int32List(_exitBuf.length * 2);
      n.setRange(0, _exitCount * 2, _exitBuf);
      _exitBuf = n;
    }
    _exitBuf[_exitCount * 2] = a;
    _exitBuf[_exitCount * 2 + 1] = b;
    _exitCount++;
  }

  // ── Main step ─────────────────────────────────────────────────────────────

  CollisionDelta step() {
    _computeAabbs();

    _currPairA.fillRange(0, _pairCap, -1);
    _currPairB.fillRange(0, _pairCap, -1);
    _currPairCount = 0;

    _broadPhase();

    _enterCount = 0;
    _stayCount = 0;
    _exitCount = 0;

    // Prev → exit (pairs that disappeared)
    for (var i = 0; i < _pairCap; i++) {
      final a = _prevPairA[i];
      if (a == -1) continue;
      final b = _prevPairB[i];
      if (!_inTable(_currPairA, _currPairB, a, b)) _appendExit(a, b);
    }

    // Curr → enter or stay
    for (var i = 0; i < _pairCap; i++) {
      final a = _currPairA[i];
      if (a == -1) continue;
      final b = _currPairB[i];
      if (_inTable(_prevPairA, _prevPairB, a, b)) {
        _appendStay(a, b);
      } else {
        _appendEnter(a, b);
      }
    }

    // Swap prev↔curr (zero-copy)
    var tmp = _prevPairA;
    _prevPairA = _currPairA;
    _currPairA = tmp;
    tmp = _prevPairB;
    _prevPairB = _currPairB;
    _currPairB = tmp;

    final enter = Int32List(_enterCount * 2)
      ..setRange(0, _enterCount * 2, _enterBuf);
    final stay = Int32List(_stayCount * 2)
      ..setRange(0, _stayCount * 2, _stayBuf);
    final exit = Int32List(_exitCount * 2)
      ..setRange(0, _exitCount * 2, _exitBuf);

    return CollisionDelta(
        enterPairs: enter, stayPairs: stay, exitPairs: exit);
  }
}
