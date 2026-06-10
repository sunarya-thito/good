import 'dart:typed_data';

import 'package:goo2d/src/data/component.dart';
import 'package:goo2d/src/physics/physics_body.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// FieldStorage — public abstract class; internal storage types implement this
// ---------------------------------------------------------------------------

abstract class FieldStorage {
  @internal
  int get byteOffset;
  @internal
  int get elementSize;
  @internal
  void writeAt(int slot, Object? value);
  @internal
  Object? readFrom(int slot);
  // Encode/decode value as raw bytes for the command-buffer capture path.
  @internal
  void writeBytes(ByteData bd, int offset, Object? value);
  @internal
  Object? readBytes(ByteData bd, int offset);
  // Called on entity creation to write non-default initial values.
  @internal
  void initSlot(int slot) {}
  @internal
  void initBytes(ByteData bd) {}
}

// ---------------------------------------------------------------------------
// QueryResult — base cursor; no entity access
// ---------------------------------------------------------------------------

abstract class QueryResult {
  T get<T extends EntityData>();

  @internal
  void setField(FieldStorage storage, Object? value);
  @internal
  Object? getField(FieldStorage storage);
}

// ---------------------------------------------------------------------------
// QueryResultWithEntity — cursor with always-valid Entity handle
// ---------------------------------------------------------------------------

abstract class QueryResultWithEntity extends QueryResult {
  Entity get entity;
}

// ---------------------------------------------------------------------------
// QueryBuilder — fluent filter API; all filter methods return this for chaining
// ---------------------------------------------------------------------------

abstract class QueryBuilder {
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
  ]);
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
  ]);
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
  ]);
  QueryBuilder withAllOf(List<Type> types);
  QueryBuilder withAnyOf(List<Type> types);
  QueryBuilder withNoneOf(List<Type> types);

  /// Returns an [EntityQueryBuilder] whose callbacks receive
  /// [QueryResultWithEntity] — always has a valid [entity] getter.
  EntityQueryBuilder withEntity();

  void forEach(void Function(QueryResult result) callback);
  QueryResult? find(bool Function(QueryResult result) predicate);
  bool any(bool Function(QueryResult result) predicate);
  bool every(bool Function(QueryResult result) predicate);
  int count();
  bool get isEmpty;
  bool get isNotEmpty;
  Iterable<QueryResult> execute();
  QueryResult? executeSingle();
}

// ---------------------------------------------------------------------------
// EntityQueryBuilder — same filters but typed for QueryResultWithEntity
// ---------------------------------------------------------------------------

abstract class EntityQueryBuilder {
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
  ]);
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
  ]);
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
  ]);
  EntityQueryBuilder withAllOf(List<Type> types);
  EntityQueryBuilder withAnyOf(List<Type> types);
  EntityQueryBuilder withNoneOf(List<Type> types);

  void forEach(void Function(QueryResultWithEntity result) callback);
  QueryResultWithEntity? find(
    bool Function(QueryResultWithEntity result) predicate,
  );
  bool any(bool Function(QueryResultWithEntity result) predicate);
  bool every(bool Function(QueryResultWithEntity result) predicate);
  int count();
  bool get isEmpty;
  bool get isNotEmpty;
  Iterable<QueryResultWithEntity> execute();
  QueryResultWithEntity? executeSingle();
}

// ---------------------------------------------------------------------------
// WorldResource
// ---------------------------------------------------------------------------

abstract class WorldResource {}

// ---------------------------------------------------------------------------
// Entity — abstract handle for a live ECS entity
// ---------------------------------------------------------------------------

abstract class Entity implements Queryable, PhysicsBody {
  int get index;

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
  ]);
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
  ]);

  void addAllData(List<DataInit> factories);
  void removeAllData(List<DataInit> factories);
  V queryData<T extends EntityData, V>(
    V Function(Fetcher fetch, T data) callback,
  );
  T getData<T extends EntityData>();
  bool hasData<T extends EntityData>();
  T? tryGetData<T extends EntityData>();
}

abstract interface class Fetcher {
  T call<T>(Field<T> field);
}

abstract interface class Queryable {}
