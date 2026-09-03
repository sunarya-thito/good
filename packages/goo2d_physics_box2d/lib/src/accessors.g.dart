// GENERATED - do not edit.
//
// Regenerate with `dart run good_tool` from
// packages/good_tool, and commit what changes.
// `dart run good_tool --check` is what CI runs; it fails if
// this file is not what the generator would write. To change a
// property, change the column it is generated from.
//
// A property here is for code touching **one** entity:
//
//   entity<Transform2D>().offsetX = 10.0;
//
// A system walking many entities resolves the component once
// per group and indexes the column instead. `component`
// re-resolves on every access, so three property lines are
// three archetype lookups - noise for one entity, and the
// thing to avoid inside a loop over thousands. See *A property
// is for one entity, a column is for many* in the design rules.
//
// Every read below is of the published snapshot, the same as
// `column[entity]`. Nothing here answers "what did I write
// earlier in this tick" - that is `column.readPending(entity)`,
// and it is reached by indexing the column.

import 'package:goo2d/goo2d.dart';
import 'package:goo2d_physics_box2d/src/rigid_body.dart';
import 'package:meta/meta.dart';

/// RigidBody2D's columns, one property each - for code
/// touching **one** entity.
///
/// A system walking many resolves the component once per
/// group and indexes the column instead. Every read here is
/// of the published snapshot.
extension Accessor$RigidBody2D on Accessor<RigidBody2D> {
  /// `bodyHandle` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.bodyHandle` instead.
  int get bodyHandle => component.bodyHandle[entity];
  set bodyHandle(int newValue) => component.bodyHandle[entity] = newValue;

  /// `bodyType` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.bodyType` instead.
  BodyType2D get bodyType => component.bodyType[entity];
  set bodyType(BodyType2D newValue) => component.bodyType[entity] = newValue;

  /// `bodyLinearVelocityX` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.bodyLinearVelocityX` instead.
  double get bodyLinearVelocityX => component.bodyLinearVelocityX[entity];
  set bodyLinearVelocityX(double newValue) =>
      component.bodyLinearVelocityX[entity] = newValue;

  /// `bodyLinearVelocityY` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.bodyLinearVelocityY` instead.
  double get bodyLinearVelocityY => component.bodyLinearVelocityY[entity];
  set bodyLinearVelocityY(double newValue) =>
      component.bodyLinearVelocityY[entity] = newValue;

  /// `bodyAngularVelocity` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.bodyAngularVelocity` instead.
  double get bodyAngularVelocity => component.bodyAngularVelocity[entity];
  set bodyAngularVelocity(double newValue) =>
      component.bodyAngularVelocity[entity] = newValue;

  /// `bodyGravityScale` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.bodyGravityScale` instead.
  double get bodyGravityScale => component.bodyGravityScale[entity];
  set bodyGravityScale(double newValue) =>
      component.bodyGravityScale[entity] = newValue;

  /// `bodyLinearDamping` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.bodyLinearDamping` instead.
  double get bodyLinearDamping => component.bodyLinearDamping[entity];
  set bodyLinearDamping(double newValue) =>
      component.bodyLinearDamping[entity] = newValue;

  /// `bodyAngularDamping` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.bodyAngularDamping` instead.
  double get bodyAngularDamping => component.bodyAngularDamping[entity];
  set bodyAngularDamping(double newValue) =>
      component.bodyAngularDamping[entity] = newValue;

  /// `bodyFixedRotation` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.bodyFixedRotation` instead.
  bool get bodyFixedRotation => component.bodyFixedRotation[entity];
  set bodyFixedRotation(bool newValue) =>
      component.bodyFixedRotation[entity] = newValue;

  /// `bodyIsBullet` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.bodyIsBullet` instead.
  bool get bodyIsBullet => component.bodyIsBullet[entity];
  set bodyIsBullet(bool newValue) => component.bodyIsBullet[entity] = newValue;

  /// `bodySyncedX` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.bodySyncedX` instead.
  @internal
  double get bodySyncedX => component.bodySyncedX[entity];
  @internal
  set bodySyncedX(double newValue) => component.bodySyncedX[entity] = newValue;

  /// `bodySyncedY` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.bodySyncedY` instead.
  @internal
  double get bodySyncedY => component.bodySyncedY[entity];
  @internal
  set bodySyncedY(double newValue) => component.bodySyncedY[entity] = newValue;

  /// `bodySyncedAngle` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.bodySyncedAngle` instead.
  @internal
  double get bodySyncedAngle => component.bodySyncedAngle[entity];
  @internal
  set bodySyncedAngle(double newValue) =>
      component.bodySyncedAngle[entity] = newValue;

  /// `bodySyncedType` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.bodySyncedType` instead.
  @internal
  BodyType2D get bodySyncedType => component.bodySyncedType[entity];
  @internal
  set bodySyncedType(BodyType2D newValue) =>
      component.bodySyncedType[entity] = newValue;
}
