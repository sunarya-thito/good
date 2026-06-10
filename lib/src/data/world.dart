import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d/src/data/component.dart'
    show entityDataGetBitmask, EntityData;
import 'package:goo2d/src/data/pool.dart';
import 'package:meta/meta.dart';

part 'command_buffer.dart';

// ---------------------------------------------------------------------------
// WorldController — public abstract interface + factory
// ---------------------------------------------------------------------------

abstract class WorldController {
  factory WorldController({int bitmaskWords}) = _WorldControllerImpl;

  QueryBuilder query();

  Entity createEntity(
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
  ]);

  Entity createEntityWith(List<DataInit> factories);
  void removeEntity(Entity entity);

  void addSystem(WorldSystem system);
  void insert(WorldSystem system, {Type? before, Type? after});
  void removeSystem(WorldSystem system);
  void dispose();

  T getResource<T extends WorldResource>();
  void setResource<T extends WorldResource>(T resource);
  bool hasResource<T extends WorldResource>();

  void broadcastEvent<T extends EventListener>(Event<T> event);
  Future<void> broadcastEventAsync<T extends EventListener>(
    AsyncEvent<T> event,
  );

  WorldCommandBuffer get commandBuffer;

  void compact();

  GameObject? get gameObject;

  @internal
  T ensureDescribed<T extends EntityData>(DataFactory<T> factory);
}

// ---------------------------------------------------------------------------
// System ordering entry
// ---------------------------------------------------------------------------

class _SystemEntry {
  final WorldSystem system;
  final Type? before;
  final Type? after;
  _SystemEntry(this.system, {this.before, this.after});
}

// ---------------------------------------------------------------------------
// QueryResult concrete classes
// ---------------------------------------------------------------------------

// execute() path — immutable slot, no entity
class _QueryResultImpl implements QueryResult {
  final int _slot;
  final MemoryPool _pool;

  _QueryResultImpl(this._slot, this._pool);

  @pragma('vm:prefer-inline')
  @override
  T get<T extends EntityData>() => _pool.getSingleton<T>();

  @pragma('vm:prefer-inline')
  @override
  void setField(FieldStorage s, Object? v) => s.writeAt(_slot, v);

  @pragma('vm:prefer-inline')
  @override
  Object? getField(FieldStorage s) => s.readFrom(_slot);
}

// execute() path — immutable slot + pre-built Entity
class _QueryResultWithEntityImpl implements QueryResultWithEntity {
  final int _slot;
  @override
  final Entity entity;
  final MemoryPool _pool;

  _QueryResultWithEntityImpl(this._slot, this.entity, this._pool);

  @pragma('vm:prefer-inline')
  @override
  T get<T extends EntityData>() => _pool.getSingleton<T>();

  @pragma('vm:prefer-inline')
  @override
  void setField(FieldStorage s, Object? v) => s.writeAt(_slot, v);

  @pragma('vm:prefer-inline')
  @override
  Object? getField(FieldStorage s) => s.readFrom(_slot);
}

// forEach() path — mutable slot, no entity (zero allocation per entity)
class _MutableQueryResult implements QueryResult {
  int _slot = 0;
  final MemoryPool _pool;

  _MutableQueryResult(this._pool);

  @pragma('vm:prefer-inline')
  @override
  T get<T extends EntityData>() => _pool.getSingleton<T>();

  @pragma('vm:prefer-inline')
  @override
  void setField(FieldStorage s, Object? v) => s.writeAt(_slot, v);

  @pragma('vm:prefer-inline')
  @override
  Object? getField(FieldStorage s) => s.readFrom(_slot);
}

// forEach() path — mutable slot + lazy Entity
class _MutableQueryResultWithEntity implements QueryResultWithEntity {
  int _slot = 0;
  Entity? _cachedEntity;
  final _WorldControllerImpl _world;

  _MutableQueryResultWithEntity(this._world);

  @override
  Entity get entity => _cachedEntity ??= _EntityImpl(
    _slot,
    _world._pool.generationAt(_slot),
    _world,
  );

  @pragma('vm:prefer-inline')
  @override
  T get<T extends EntityData>() => _world._pool.getSingleton<T>();

  @pragma('vm:prefer-inline')
  @override
  void setField(FieldStorage s, Object? v) => s.writeAt(_slot, v);

  @pragma('vm:prefer-inline')
  @override
  Object? getField(FieldStorage s) => s.readFrom(_slot);
}

// Capture path — writes field values directly into _buf during withInit at enqueue time
class _CaptureQueryResult implements QueryResult {
  final MemoryPool _pool;
  Int64List _buf = Int64List(0);
  ByteData _bd = ByteData(0);
  int _initByteBase = 0;

  _CaptureQueryResult(this._pool);

  void _update(Int64List buf, int initByteBase) {
    if (!identical(_buf, buf)) {
      _buf = buf;
      _bd = ByteData.view(buf.buffer, buf.offsetInBytes);
    }
    _initByteBase = initByteBase;
  }

  @pragma('vm:prefer-inline')
  @override
  T get<T extends EntityData>() => _pool.getSingleton<T>();

  @override
  void setField(FieldStorage s, Object? v) =>
      s.writeBytes(_bd, _initByteBase + s.byteOffset, v);

  @override
  Object? getField(FieldStorage s) =>
      s.readBytes(_bd, _initByteBase + s.byteOffset);
}

// ---------------------------------------------------------------------------
// QueryBuilder
// ---------------------------------------------------------------------------

class _QueryBuilderImpl implements QueryBuilder {
  final MemoryPool _pool;
  final _WorldControllerImpl _world;

  late final Int64List _allMask = Int64List(_pool.bitmaskWords);
  late final Int64List _noneMask = Int64List(_pool.bitmaskWords);
  late final Int64List _anyMask = Int64List(_pool.bitmaskWords);
  bool _hasAll = false, _hasNone = false, _hasAny = false;
  bool _allImpossible = false;

  _QueryBuilderImpl(this._pool, this._world);

  @pragma('vm:prefer-inline')
  void _stamp(Int64List mask, bool isAll, List<Type?> types) {
    for (final t in types) {
      if (t == null) break;
      final int bit;
      switch (t) {
        case final EntityData ed:
          bit = entityDataGetBitmask(ed);
        default:
          final b = _pool.tryBitIndexOf(t);
          if (b == null) {
            if (isAll) _allImpossible = true;
            continue;
          }
          bit = b;
      }
      mask[bit >> 6] |= 1 << (bit & 63);
    }
  }

  @pragma('vm:prefer-inline')
  void _stampList(Int64List mask, bool isAll, List<Type> types) {
    for (final t in types) {
      final int bit;
      switch (t) {
        case final EntityData ed:
          bit = entityDataGetBitmask(ed);
        default:
          final b = _pool.tryBitIndexOf(t);
          if (b == null) {
            if (isAll) _allImpossible = true;
            continue;
          }
          bit = b;
      }
      mask[bit >> 6] |= 1 << (bit & 63);
    }
  }

  @override
  QueryBuilder withAll(
    Type a, [
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]) {
    _stamp(_allMask, true, [a, b, c, d, e, f, g, h, i, j]);
    _hasAll = true;
    return this;
  }

  @override
  QueryBuilder withAny(
    Type a, [
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]) {
    _stamp(_anyMask, false, [a, b, c, d, e, f, g, h, i, j]);
    _hasAny = true;
    return this;
  }

  @override
  QueryBuilder withNone(
    Type a, [
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]) {
    _stamp(_noneMask, false, [a, b, c, d, e, f, g, h, i, j]);
    _hasNone = true;
    return this;
  }

  @override
  QueryBuilder withAllOf(List<Type> types) {
    _stampList(_allMask, true, types);
    _hasAll = true;
    return this;
  }

  @override
  QueryBuilder withAnyOf(List<Type> types) {
    _stampList(_anyMask, false, types);
    _hasAny = true;
    return this;
  }

  @override
  QueryBuilder withNoneOf(List<Type> types) {
    _stampList(_noneMask, false, types);
    _hasNone = true;
    return this;
  }

  @override
  EntityQueryBuilder withEntity() => _EntityQueryBuilderImpl(this);

  @pragma('vm:prefer-inline')
  bool _passes(Int64List entities, int base, int words) {
    if (_allImpossible) return false;
    if (_hasAll) {
      for (int w = 0; w < words; w++) {
        if ((entities[base + w] & _allMask[w]) != _allMask[w]) return false;
      }
    }
    if (_hasNone) {
      for (int w = 0; w < words; w++) {
        if ((entities[base + w] & _noneMask[w]) != 0) return false;
      }
    }
    if (_hasAny) {
      for (int w = 0; w < words; w++) {
        if ((entities[base + w] & _anyMask[w]) != 0) return true;
      }
      return false;
    }
    return true;
  }

  @override
  Iterable<QueryResult> execute() sync* {
    final entities = _pool.rawEntities;
    final stride = _pool.stride;
    final words = _pool.bitmaskWords;
    for (int slot = 0; slot < _pool.count; slot++) {
      if (entities[slot * stride] < 0) continue;
      if (!_passes(entities, slot * stride + 1, words)) continue;
      yield _QueryResultImpl(slot, _pool);
    }
  }

  Iterable<QueryResultWithEntity> _executeWithEntity() sync* {
    final entities = _pool.rawEntities;
    final stride = _pool.stride;
    final words = _pool.bitmaskWords;
    for (int slot = 0; slot < _pool.count; slot++) {
      if (entities[slot * stride] < 0) continue;
      if (!_passes(entities, slot * stride + 1, words)) continue;
      yield _QueryResultWithEntityImpl(
        slot,
        _EntityImpl(slot, entities[slot * stride], _world),
        _pool,
      );
    }
  }

  @override
  void forEach(void Function(QueryResult) callback) {
    final entities = _pool.rawEntities;
    final stride = _pool.stride;
    final words = _pool.bitmaskWords;
    final result = _MutableQueryResult(_pool);
    for (int slot = 0; slot < _pool.count; slot++) {
      if (entities[slot * stride] < 0) continue;
      if (!_passes(entities, slot * stride + 1, words)) continue;
      result._slot = slot;
      callback(result);
    }
  }

  void _forEachWithEntity(void Function(QueryResultWithEntity) callback) {
    final entities = _pool.rawEntities;
    final stride = _pool.stride;
    final words = _pool.bitmaskWords;
    final result = _MutableQueryResultWithEntity(_world);
    for (int slot = 0; slot < _pool.count; slot++) {
      if (entities[slot * stride] < 0) continue;
      if (!_passes(entities, slot * stride + 1, words)) continue;
      result._slot = slot;
      result._cachedEntity = null;
      callback(result);
    }
  }

  @override
  QueryResult? find(bool Function(QueryResult) predicate) {
    final entities = _pool.rawEntities;
    final stride = _pool.stride;
    final words = _pool.bitmaskWords;
    final result = _MutableQueryResult(_pool);
    for (int slot = 0; slot < _pool.count; slot++) {
      if (entities[slot * stride] < 0) continue;
      if (!_passes(entities, slot * stride + 1, words)) continue;
      result._slot = slot;
      if (predicate(result)) return _QueryResultImpl(slot, _pool);
    }
    return null;
  }

  QueryResultWithEntity? _findWithEntity(
    bool Function(QueryResultWithEntity) predicate,
  ) {
    final entities = _pool.rawEntities;
    final stride = _pool.stride;
    final words = _pool.bitmaskWords;
    final result = _MutableQueryResultWithEntity(_world);
    for (int slot = 0; slot < _pool.count; slot++) {
      if (entities[slot * stride] < 0) continue;
      if (!_passes(entities, slot * stride + 1, words)) continue;
      result._slot = slot;
      result._cachedEntity = null;
      if (predicate(result)) {
        return _QueryResultWithEntityImpl(
          slot,
          _EntityImpl(slot, entities[slot * stride], _world),
          _pool,
        );
      }
    }
    return null;
  }

  @override
  bool any(bool Function(QueryResult) predicate) {
    final entities = _pool.rawEntities;
    final stride = _pool.stride;
    final words = _pool.bitmaskWords;
    final result = _MutableQueryResult(_pool);
    for (int slot = 0; slot < _pool.count; slot++) {
      if (entities[slot * stride] < 0) continue;
      if (!_passes(entities, slot * stride + 1, words)) continue;
      result._slot = slot;
      if (predicate(result)) return true;
    }
    return false;
  }

  bool _anyWithEntity(bool Function(QueryResultWithEntity) predicate) {
    final entities = _pool.rawEntities;
    final stride = _pool.stride;
    final words = _pool.bitmaskWords;
    final result = _MutableQueryResultWithEntity(_world);
    for (int slot = 0; slot < _pool.count; slot++) {
      if (entities[slot * stride] < 0) continue;
      if (!_passes(entities, slot * stride + 1, words)) continue;
      result._slot = slot;
      result._cachedEntity = null;
      if (predicate(result)) return true;
    }
    return false;
  }

  @override
  bool every(bool Function(QueryResult) predicate) {
    final entities = _pool.rawEntities;
    final stride = _pool.stride;
    final words = _pool.bitmaskWords;
    final result = _MutableQueryResult(_pool);
    for (int slot = 0; slot < _pool.count; slot++) {
      if (entities[slot * stride] < 0) continue;
      if (!_passes(entities, slot * stride + 1, words)) continue;
      result._slot = slot;
      if (!predicate(result)) return false;
    }
    return true;
  }

  bool _everyWithEntity(bool Function(QueryResultWithEntity) predicate) {
    final entities = _pool.rawEntities;
    final stride = _pool.stride;
    final words = _pool.bitmaskWords;
    final result = _MutableQueryResultWithEntity(_world);
    for (int slot = 0; slot < _pool.count; slot++) {
      if (entities[slot * stride] < 0) continue;
      if (!_passes(entities, slot * stride + 1, words)) continue;
      result._slot = slot;
      result._cachedEntity = null;
      if (!predicate(result)) return false;
    }
    return true;
  }

  @override
  int count() {
    final entities = _pool.rawEntities;
    final stride = _pool.stride;
    final words = _pool.bitmaskWords;
    int n = 0;
    for (int slot = 0; slot < _pool.count; slot++) {
      if (entities[slot * stride] < 0) continue;
      if (_passes(entities, slot * stride + 1, words)) n++;
    }
    return n;
  }

  @override
  bool get isEmpty {
    final entities = _pool.rawEntities;
    final stride = _pool.stride;
    final words = _pool.bitmaskWords;
    for (int slot = 0; slot < _pool.count; slot++) {
      if (entities[slot * stride] < 0) continue;
      if (_passes(entities, slot * stride + 1, words)) return false;
    }
    return true;
  }

  @override
  bool get isNotEmpty => !isEmpty;

  @override
  QueryResult? executeSingle() => find((_) => true);
}

// ---------------------------------------------------------------------------
// EntityQueryBuilder adapter
// ---------------------------------------------------------------------------

class _EntityQueryBuilderImpl implements EntityQueryBuilder {
  final _QueryBuilderImpl _inner;

  _EntityQueryBuilderImpl(this._inner);

  @override
  EntityQueryBuilder withAll(
    Type a, [
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]) {
    _inner.withAll(a, b, c, d, e, f, g, h, i, j);
    return this;
  }

  @override
  EntityQueryBuilder withAny(
    Type a, [
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]) {
    _inner.withAny(a, b, c, d, e, f, g, h, i, j);
    return this;
  }

  @override
  EntityQueryBuilder withNone(
    Type a, [
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]) {
    _inner.withNone(a, b, c, d, e, f, g, h, i, j);
    return this;
  }

  @override
  EntityQueryBuilder withAllOf(List<Type> types) {
    _inner.withAllOf(types);
    return this;
  }

  @override
  EntityQueryBuilder withAnyOf(List<Type> types) {
    _inner.withAnyOf(types);
    return this;
  }

  @override
  EntityQueryBuilder withNoneOf(List<Type> types) {
    _inner.withNoneOf(types);
    return this;
  }

  @override
  void forEach(void Function(QueryResultWithEntity) callback) =>
      _inner._forEachWithEntity(callback);

  @override
  QueryResultWithEntity? find(bool Function(QueryResultWithEntity) predicate) =>
      _inner._findWithEntity(predicate);

  @override
  bool any(bool Function(QueryResultWithEntity) predicate) =>
      _inner._anyWithEntity(predicate);

  @override
  bool every(bool Function(QueryResultWithEntity) predicate) =>
      _inner._everyWithEntity(predicate);

  @override
  int count() => _inner.count();

  @override
  bool get isEmpty => _inner.isEmpty;

  @override
  bool get isNotEmpty => _inner.isNotEmpty;

  @override
  Iterable<QueryResultWithEntity> execute() => _inner._executeWithEntity();

  @override
  QueryResultWithEntity? executeSingle() => _inner._findWithEntity((_) => true);
}

// ---------------------------------------------------------------------------
// Entity
// ---------------------------------------------------------------------------

class _EntityImpl implements Entity {
  @override
  final int index;
  final int _generation;
  final _WorldControllerImpl _world;

  _EntityImpl(this.index, this._generation, this._world);

  @pragma('vm:prefer-inline')
  void _assertAlive() {
    assert(
      _world._pool.generationAt(index) == _generation,
      'Stale entity reference — entity at slot $index has been destroyed',
    );
  }

  @override
  void addAllData(List<DataInit> factories) {
    _assertAlive();
    _world._mutateAdd(index, factories);
  }

  @override
  void removeAllData(List<DataInit> factories) {
    _assertAlive();
    _world._mutateRemove(index, factories);
  }

  @pragma('vm:prefer-inline')
  @override
  T getData<T extends EntityData>() {
    _assertAlive();
    return _world._pool.getSingleton<T>();
  }

  @pragma('vm:prefer-inline')
  @override
  bool hasData<T extends EntityData>() {
    _assertAlive();
    return _world._pool.hasComponent(index, T);
  }

  @pragma('vm:prefer-inline')
  @override
  T? tryGetData<T extends EntityData>() {
    _assertAlive();
    return hasData<T>() ? _world._pool.getSingleton<T>() : null;
  }

  @override
  V queryData<T extends EntityData, V>(
    V Function(Fetcher fetch, T data) callback,
  ) {
    _assertAlive();
    final data = _world._pool.getSingleton<T>();
    return callback(_FetcherImpl(index), data);
  }

  @override
  int get colliderHandle {
    _assertAlive();
    return tryGetData<ColliderData>()?.colliderHandle.getSlot(index) ?? -1;
  }

  @override
  void addData(
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
    _assertAlive();
    addAllData([a, ?b, ?c, ?d, ?e, ?f, ?g, ?h, ?i, ?j]);
  }

  @override
  void removeData(
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
    _assertAlive();
    removeAllData([a, ?b, ?c, ?d, ?e, ?f, ?g, ?h, ?i, ?j]);
  }
}

class _FetcherImpl implements Fetcher {
  final int _slot;
  _FetcherImpl(this._slot);

  @override
  T call<T>(Field<T> field) => field.getSlot(_slot);
}

// ---------------------------------------------------------------------------
// _WorldController — concrete WorldController
// ---------------------------------------------------------------------------

class _WorldControllerImpl implements WorldController {
  final MemoryPool _pool;

  _WorldControllerImpl({int bitmaskWords = 2})
    : _pool = MemoryPool(bitmaskWords: bitmaskWords);

  GameObject? _gameObject;
  @override
  GameObject? get gameObject => _gameObject;

  final List<_SystemEntry> _entries = [];
  final Map<Type, WorldResource> _resources = {};

  List<WorldSystem>? _sortedSystems;
  final Map<Type, ({List<WorldSystem> list, bool Function(Object) accepts})>
  _listenerCache = {};

  int _iterating = 0;

  @override
  late final WorldCommandBuffer commandBuffer = WorldCommandBuffer(this);

  // ---- entity lifecycle ----

  static DataFactory _rawFactory(DataInit di) =>
      di is DataFactoryWithInit ? di.dataFactory : di as DataFactory;

  @override
  Entity createEntity(
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
  ]) => createEntityWith([a, ?b, ?c, ?d, ?e, ?f, ?g, ?h, ?i, ?j]);

  @override
  Entity createEntityWith(List<DataInit> dataInits) {
    assert(
      _iterating == 0,
      'Cannot create entities during tick. Use a command buffer.',
    );
    final types = <Type>[];
    final inits = <(EntityData, void Function(EntityData, QueryResult))>[];
    for (final di in dataInits) {
      final factory = _rawFactory(di);
      final type = _pool.ensureDescribedRuntime(factory);
      types.add(type);
      if (di is DataFactoryWithInit) {
        inits.add((_pool.getSingletonByType(type), di.applyInit));
      }
    }
    final slot = _pool.allocate(types);
    if (inits.isNotEmpty) {
      final cursor = _MutableQueryResult(_pool).._slot = slot;
      for (final (singleton, init) in inits) {
        init(singleton, cursor);
      }
    }
    return _EntityImpl(slot, _pool.generationAt(slot), this);
  }

  @override
  void removeEntity(Entity entity) {
    assert(
      _iterating == 0,
      'Cannot remove entities during tick. Use a command buffer.',
    );
    final impl = entity as _EntityImpl;
    assert(
      _pool.generationAt(impl.index) == impl._generation,
      'Attempted to remove a stale entity reference',
    );
    _pool.free(impl.index);
  }

  @override
  T ensureDescribed<T extends EntityData>(DataFactory<T> factory) {
    _pool.ensureDescribedRuntime(factory);
    return _pool.getSingleton<T>();
  }

  void _mutateAdd(int slot, List<DataInit> dataInits) {
    assert(
      _iterating == 0,
      'Cannot add/remove data during tick. Use a command buffer.',
    );
    for (final di in dataInits) {
      final factory = _rawFactory(di);
      final type = _pool.ensureDescribedRuntime(factory);
      _pool.addComponent(slot, type);
      if (di is DataFactoryWithInit) {
        final cursor = _MutableQueryResult(_pool).._slot = slot;
        di.applyInit(_pool.getSingletonByType(type), cursor);
      }
    }
  }

  void _mutateRemove(int slot, List<DataInit> dataInits) {
    assert(
      _iterating == 0,
      'Cannot add/remove data during tick. Use a command buffer.',
    );
    for (final di in dataInits) {
      _pool.removeComponent(
        slot,
        _pool.ensureDescribedRuntime(_rawFactory(di)),
      );
    }
  }

  // ---- query ----

  @override
  QueryBuilder query() => _QueryBuilderImpl(_pool, this);

  // ---- system management ----

  @override
  void addSystem(WorldSystem system) =>
      insert(system, before: system.systemBefore, after: system.systemAfter);

  @override
  void insert(WorldSystem system, {Type? before, Type? after}) {
    system.attachToWorld(this);
    system.onAttach();
    _entries.add(_SystemEntry(system, before: before, after: after));
    _sortedSystems = _topoSort(_entries);
    final globalIdx = _sortedSystems!.indexOf(system);
    for (final entry in _listenerCache.values) {
      if (!entry.accepts(system)) continue;
      int insertIdx = entry.list.length;
      for (int i = 0; i < entry.list.length; i++) {
        if (_sortedSystems!.indexOf(entry.list[i]) > globalIdx) {
          insertIdx = i;
          break;
        }
      }
      entry.list.insert(insertIdx, system);
    }
  }

  @override
  void removeSystem(WorldSystem system) {
    _entries.removeWhere((e) => e.system == system);
    system.onDetach();
    _sortedSystems?.remove(system);
    for (final entry in _listenerCache.values) {
      entry.list.remove(system);
    }
  }

  @override
  void dispose() {
    for (final entry in List.of(_entries)) {
      removeSystem(entry.system);
    }
  }

  // ---- resources ----

  @override
  T getResource<T extends WorldResource>() {
    assert(_resources.containsKey(T), 'WorldResource $T has not been set');
    return _resources[T] as T;
  }

  @override
  void setResource<T extends WorldResource>(T resource) {
    _resources[T] = resource;
  }

  @override
  bool hasResource<T extends WorldResource>() => _resources.containsKey(T);

  // ---- event broadcast to systems ----

  List<WorldSystem> _listenersOf<T extends EventListener>() {
    final existing = _listenerCache[T];
    if (existing != null) return existing.list;
    _sortedSystems ??= _topoSort(_entries);
    List<WorldSystem> build() =>
        _sortedSystems!.whereType<T>().cast<WorldSystem>().toList();
    _listenerCache[T] = (list: build(), accepts: (s) => s is T);
    return _listenerCache[T]!.list;
  }

  @override
  void broadcastEvent<T extends EventListener>(Event<T> event) {
    _iterating++;
    try {
      for (final system in _listenersOf<T>()) {
        system.onDispatchEvent(event);
      }
    } finally {
      _iterating--;
    }
    if (_iterating == 0) commandBuffer._flush();
  }

  @override
  Future<void> broadcastEventAsync<T extends EventListener>(
    AsyncEvent<T> event,
  ) async {
    _iterating++;
    try {
      for (final system in _listenersOf<T>().toList(growable: false)) {
        await system.onDispatchEventAsync(event);
      }
    } finally {
      _iterating--;
    }
    if (_iterating == 0) commandBuffer._flush();
  }

  // ---- compaction ----

  @override
  void compact() {
    assert(_iterating == 0, 'Cannot compact during tick');
    _pool.compact();
  }

  // ---- topological sort ----

  static List<WorldSystem> _topoSort(List<_SystemEntry> entries) {
    if (entries.isEmpty) return [];

    final byType = <Type, _SystemEntry>{};
    for (final e in entries) {
      byType[e.system.runtimeType] = e;
    }

    final inDegree = <Type, int>{for (final t in byType.keys) t: 0};
    final adj = <Type, List<Type>>{for (final t in byType.keys) t: []};

    for (final e in entries) {
      final type = e.system.runtimeType;
      if (e.after != null && byType.containsKey(e.after)) {
        adj[e.after]!.add(type);
        inDegree[type] = inDegree[type]! + 1;
      }
      if (e.before != null && byType.containsKey(e.before)) {
        adj[type]!.add(e.before!);
        inDegree[e.before!] = inDegree[e.before!]! + 1;
      }
    }

    final queue = Queue<Type>()
      ..addAll(inDegree.entries.where((e) => e.value == 0).map((e) => e.key));
    final sorted = <WorldSystem>[];

    while (queue.isNotEmpty) {
      final type = queue.removeFirst();
      sorted.add(byType[type]!.system);
      for (final neighbor in adj[type]!) {
        inDegree[neighbor] = inDegree[neighbor]! - 1;
        if (inDegree[neighbor] == 0) queue.add(neighbor);
      }
    }

    assert(
      sorted.length == entries.length,
      'Circular dependency detected in WorldSystem ordering',
    );

    return sorted;
  }
}

// ---------------------------------------------------------------------------
// World — Flutter widget that drives a WorldController
// ---------------------------------------------------------------------------

class World extends StatefulGameWidget {
  final WorldController controller;

  const World(this.controller, {super.key});

  @override
  GameState<World> createState() => _WorldState();
}

class _WorldState extends GameState<World> with LifecycleListener {
  WorldController get _world => widget.controller;
  _WorldControllerImpl get _worldImpl => _world as _WorldControllerImpl;

  @override
  void onMounted() => _worldImpl._gameObject = gameObject;
  @override
  void onUnmounted() => _worldImpl._gameObject = null;

  @override
  bool onDispatchEvent<T extends EventListener>(Event<T> event) {
    final accepted = super.onDispatchEvent(event);
    _world.broadcastEvent(event);
    return accepted;
  }

  @override
  Future<bool> onDispatchEventAsync<T extends EventListener>(
    AsyncEvent<T> event,
  ) async {
    final accepted = await super.onDispatchEventAsync(event);
    await _world.broadcastEventAsync(event);
    return accepted;
  }

  @override
  Iterable<Widget> build(BuildContext context) => const [];
}
