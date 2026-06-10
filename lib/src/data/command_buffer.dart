part of 'world.dart';

// ---------------------------------------------------------------------------
// Opcode constants
// ---------------------------------------------------------------------------

const int _kCbCreate = 0;
const int _kCbRemove = 1;
const int _kCbAddData = 2;
const int _kCbRemoveData = 3;

// ---------------------------------------------------------------------------
// WorldCommandBuffer
//
// Variable-length commands in a single Int64List.
//
// Per-command layout when extraWords == 0:
//   [header(1)] [main-bitmask(bitmaskWords)]
//
// Per-command layout when extraWords > 0  (withInit present):
//   [header(1)] [main-bitmask(bitmaskWords)]
//   [init-type-bitmask(bitmaskWords)] [init-data(extraWords - bitmaskWords)]
//
// header (Int64):
//   bits  0-15  entitySlot (0 for createEntity)
//   bits 16-23  opcode
//   bits 24-31  extraWords  (0 = no init data; else bitmaskWords + initDataWords)
//   bits 32-63  entityGen   (lower 32 bits; 0 for createEntity)
//
// Flush scans sequentially: pos += 1 + bitmaskWords + extraWords.
// ---------------------------------------------------------------------------

class WorldCommandBuffer {
  static const int _initialWords = 256;

  final _WorldControllerImpl _world;
  Int64List _buf = Int64List(_initialWords);
  int _used = 0;
  late final _CaptureQueryResult _captureResult = _CaptureQueryResult(
    _world._pool,
  );

  WorldCommandBuffer(WorldController world)
    : _world = world as _WorldControllerImpl;

  // ---- buffer growth ----

  void _ensureSpace(int words) {
    if (_used + words <= _buf.length) return;
    var next = _buf.length;
    while (_used + words > next) {
      next *= 2;
    }
    final newBuf = Int64List(next);
    newBuf.setRange(0, _used, _buf);
    _buf = newBuf;
  }

  int get _bw => _world._pool.bitmaskWords;

  // ---- type stamping ----

  void _stampType(DataInit di, int bitmaskBase) {
    final factory = _WorldControllerImpl._rawFactory(di);
    final type = _world._pool.ensureDescribedRuntime(factory);
    final bit = _world._pool.bitIndexOf(type);
    _buf[bitmaskBase + (bit >> 6)] |= (1 << (bit & 63));
  }

  // ---- header ----

  void _writeHeader(int pos, int slot, int opcode, int gen, int extraWords) {
    _buf[pos] =
        ((gen & 0xFFFFFFFF) << 32) |
        (extraWords << 24) |
        (opcode << 16) |
        (slot & 0xFFFF);
  }

  // ---- enqueue ----

  // Enqueue for ops with no type bitmask (removeEntity uses gen+slot only).
  void _enqueueNoTypes(int slot, int opcode, int gen) {
    final bw = _bw;
    _ensureSpace(1 + bw);
    _writeHeader(_used, slot, opcode, gen, 0);
    _used += 1 + bw;
  }

  // Enqueue with bitmask only — no withInit.
  void _enqueueSimpleList(int slot, int opcode, int gen, List<DataInit> inits) {
    final bw = _bw;
    _ensureSpace(1 + bw);
    final base = _used;
    _writeHeader(base, slot, opcode, gen, 0);
    for (final di in inits) {
      _stampType(di, base + 1);
    }
    _used += 1 + bw;
  }

  // Enqueue with possible withInit support.
  void _enqueueWithPossibleInit(
    int slot,
    int opcode,
    int gen,
    List<DataInit> dataInits,
  ) {
    final pool = _world._pool;
    final bw = pool.bitmaskWords;

    // Register all types.
    for (final di in dataInits) {
      pool.ensureDescribedRuntime(_WorldControllerImpl._rawFactory(di));
    }

    // Collect withInit types.
    final initTypeSet = <Type>{};
    for (final di in dataInits) {
      if (di is DataFactoryWithInit) {
        initTypeSet.add(pool.ensureDescribedRuntime(di.dataFactory));
      }
    }

    if (initTypeSet.isEmpty) {
      // Fast path — no init data.
      _ensureSpace(1 + bw);
      final base = _used;
      _writeHeader(base, slot, opcode, gen, 0);
      for (final di in dataInits) {
        _stampType(di, base + 1);
      }
      _used += 1 + bw;
      return;
    }

    // Compute layout sizes.
    final initDataWords = pool.initDataWordCount(initTypeSet);
    final extraWords = bw + initDataWords; // init-bitmask + init-data

    _ensureSpace(1 + bw + extraWords);
    final base = _used;
    _writeHeader(base, slot, opcode, gen, extraWords);

    // Stamp main bitmask.
    for (final di in dataInits) {
      _stampType(di, base + 1);
    }

    final initBitmaskBase = base + 1 + bw;
    final initDataWordBase = base + 1 + 2 * bw;

    // Zero init data region.
    for (int i = 0; i < initDataWords; i++) {
      _buf[initDataWordBase + i] = 0;
    }

    // Build type → DataFactoryWithInit lookup.
    final initMap = <Type, DataFactoryWithInit>{};
    for (final di in dataInits) {
      if (di is DataFactoryWithInit) {
        initMap[pool.ensureDescribedRuntime(di.dataFactory)] = di;
      }
    }

    // Capture init data in registration order.
    pool.foreachInitType(
      initTypeSet,
      _buf,
      initBitmaskBase,
      initDataWordBase,
      (type, singleton, initByteBase) {
        _captureResult._update(_buf, initByteBase);
        initMap[type]!.applyInit(singleton, _captureResult);
      },
    );

    _used += 1 + bw + extraWords;
  }

  // ---- public API ----

  void createEntity(
    DataInit a, [
    DataInit? b,
    DataInit? c,
    DataInit? d,
    DataInit? e,
    DataInit? f,
    DataInit? g,
    DataInit? h,
    DataInit? i,
    DataInit? j,
  ]) => _enqueueWithPossibleInit(0, _kCbCreate, 0, [
    a,
    ?b,
    ?c,
    ?d,
    ?e,
    ?f,
    ?g,
    ?h,
    ?i,
    ?j,
  ]);

  void createEntityAll(List<DataInit> factories) =>
      _enqueueWithPossibleInit(0, _kCbCreate, 0, factories);

  void removeEntity(Entity entity) {
    final impl = entity as _EntityImpl;
    _enqueueNoTypes(impl.index, _kCbRemove, impl._generation);
  }

  void addData(
    Entity entity,
    DataInit a, [
    DataInit? b,
    DataInit? c,
    DataInit? d,
    DataInit? e,
    DataInit? f,
    DataInit? g,
    DataInit? h,
    DataInit? i,
    DataInit? j,
  ]) {
    final impl = entity as _EntityImpl;
    _enqueueWithPossibleInit(impl.index, _kCbAddData, impl._generation, [
      a,
      ?b,
      ?c,
      ?d,
      ?e,
      ?f,
      ?g,
      ?h,
      ?i,
      ?j,
    ]);
  }

  void addDataAll(Entity entity, List<DataInit> factories) {
    final impl = entity as _EntityImpl;
    _enqueueWithPossibleInit(
      impl.index,
      _kCbAddData,
      impl._generation,
      factories,
    );
  }

  void removeData(
    Entity entity,
    DataInit a, [
    DataInit? b,
    DataInit? c,
    DataInit? d,
    DataInit? e,
    DataInit? f,
    DataInit? g,
    DataInit? h,
    DataInit? i,
    DataInit? j,
  ]) {
    final impl = entity as _EntityImpl;
    _enqueueSimpleList(impl.index, _kCbRemoveData, impl._generation, [
      a,
      ?b,
      ?c,
      ?d,
      ?e,
      ?f,
      ?g,
      ?h,
      ?i,
      ?j,
    ]);
  }

  void removeDataAll(Entity entity, List<DataInit> factories) {
    final impl = entity as _EntityImpl;
    _enqueueSimpleList(impl.index, _kCbRemoveData, impl._generation, factories);
  }

  // ---- flush ----

  void _flush() {
    final pool = _world._pool;
    final bw = pool.bitmaskWords;
    int pos = 0;
    while (pos < _used) {
      final w0 = _buf[pos];
      final slot = (w0 & 0xFFFF).toInt();
      final opcode = (w0 >>> 16) & 0xFF;
      final extraWords = (w0 >>> 24) & 0xFF;
      final gen = (w0 >>> 32) & 0xFFFFFFFF;
      final bitmaskBase = pos + 1;
      final initBitmaskBase = pos + 1 + bw;
      final initDataWordBase = pos + 1 + 2 * bw;

      switch (opcode) {
        case _kCbCreate:
          if (extraWords == 0) {
            pool.allocateWithBits(_buf, bitmaskBase);
          } else {
            final realSlot = pool.allocateWithBitsAndInit(
              _buf,
              bitmaskBase,
              _buf,
              initBitmaskBase,
            );
            pool.unpackInitData(
              _buf,
              initBitmaskBase,
              initDataWordBase,
              realSlot,
            );
          }
        case _kCbRemove:
          assert(
            pool.generationAt(slot) & 0xFFFFFFFF == gen,
            'Stale entity in WorldCommandBuffer (removeEntity)',
          );
          pool.free(slot);
        case _kCbAddData:
          assert(
            pool.generationAt(slot) & 0xFFFFFFFF == gen,
            'Stale entity in WorldCommandBuffer (addData)',
          );
          if (extraWords == 0) {
            pool.addBits(slot, _buf, bitmaskBase);
          } else {
            pool.addBitsAndInit(slot, _buf, bitmaskBase, _buf, initBitmaskBase);
            pool.unpackInitData(_buf, initBitmaskBase, initDataWordBase, slot);
          }
        case _kCbRemoveData:
          assert(
            pool.generationAt(slot) & 0xFFFFFFFF == gen,
            'Stale entity in WorldCommandBuffer (removeData)',
          );
          pool.removeBits(slot, _buf, bitmaskBase);
      }

      pos += 1 + bw + extraWords;
    }

    // Zero used words to clear bitmask/init bits.
    for (int i = 0; i < _used; i++) {
      _buf[i] = 0;
    }
    _used = 0;
    _world._pool.clearHeapCapture();
  }
}
