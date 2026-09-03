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

import 'package:goo3d/src/data/camera.dart';
import 'package:goo3d/src/data/transform.dart';
import 'package:goo3d/src/data/world_transform.dart';
import 'package:good/good.dart';

/// Camera3D's columns, one property each - for code
/// touching **one** entity.
///
/// A system walking many resolves the component once per
/// group and indexes the column instead. Every read here is
/// of the published snapshot.
extension Accessor$Camera3D on Accessor<Camera3D> {
  /// `cameraFieldOfView` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.cameraFieldOfView` instead.
  double get fieldOfView => component.cameraFieldOfView[entity];
  set fieldOfView(double newValue) =>
      component.cameraFieldOfView[entity] = newValue;

  /// `cameraNear` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.cameraNear` instead.
  double get near => component.cameraNear[entity];
  set near(double newValue) => component.cameraNear[entity] = newValue;

  /// `cameraFar` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.cameraFar` instead.
  double get far => component.cameraFar[entity];
  set far(double newValue) => component.cameraFar[entity] = newValue;

  /// `cameraView` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.cameraView` instead.
  CameraView? get view => component.cameraView[entity];
  set view(CameraView? newValue) => component.cameraView[entity] = newValue;
}

/// Transform3D's columns, one property each - for code
/// touching **one** entity.
///
/// A system walking many resolves the component once per
/// group and indexes the column instead. Every read here is
/// of the published snapshot.
extension Accessor$Transform3D on Accessor<Transform3D> {
  /// `transformOffsetX` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.transformOffsetX` instead.
  double get offsetX => component.transformOffsetX[entity];
  set offsetX(double newValue) => component.transformOffsetX[entity] = newValue;

  /// `transformOffsetY` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.transformOffsetY` instead.
  double get offsetY => component.transformOffsetY[entity];
  set offsetY(double newValue) => component.transformOffsetY[entity] = newValue;

  /// `transformOffsetZ` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.transformOffsetZ` instead.
  double get offsetZ => component.transformOffsetZ[entity];
  set offsetZ(double newValue) => component.transformOffsetZ[entity] = newValue;

  /// `transformScaleX` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.transformScaleX` instead.
  double get scaleX => component.transformScaleX[entity];
  set scaleX(double newValue) => component.transformScaleX[entity] = newValue;

  /// `transformScaleY` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.transformScaleY` instead.
  double get scaleY => component.transformScaleY[entity];
  set scaleY(double newValue) => component.transformScaleY[entity] = newValue;

  /// `transformScaleZ` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.transformScaleZ` instead.
  double get scaleZ => component.transformScaleZ[entity];
  set scaleZ(double newValue) => component.transformScaleZ[entity] = newValue;

  /// `transformRotationX` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.transformRotationX` instead.
  double get rotationX => component.transformRotationX[entity];
  set rotationX(double newValue) =>
      component.transformRotationX[entity] = newValue;

  /// `transformRotationY` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.transformRotationY` instead.
  double get rotationY => component.transformRotationY[entity];
  set rotationY(double newValue) =>
      component.transformRotationY[entity] = newValue;

  /// `transformRotationZ` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.transformRotationZ` instead.
  double get rotationZ => component.transformRotationZ[entity];
  set rotationZ(double newValue) =>
      component.transformRotationZ[entity] = newValue;

  /// `transformRotationW` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.transformRotationW` instead.
  double get rotationW => component.transformRotationW[entity];
  set rotationW(double newValue) =>
      component.transformRotationW[entity] = newValue;
}

/// WorldTransform3D's columns, one property each - for code
/// touching **one** entity.
///
/// A system walking many resolves the component once per
/// group and indexes the column instead. Every read here is
/// of the published snapshot.
extension Accessor$WorldTransform3D on Accessor<WorldTransform3D> {
  /// `worldX` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.worldX` instead.
  double get worldX => component.worldX[entity];
  set worldX(double newValue) => component.worldX[entity] = newValue;

  /// `worldY` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.worldY` instead.
  double get worldY => component.worldY[entity];
  set worldY(double newValue) => component.worldY[entity] = newValue;

  /// `worldZ` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.worldZ` instead.
  double get worldZ => component.worldZ[entity];
  set worldZ(double newValue) => component.worldZ[entity] = newValue;

  /// `worldScaleX` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.worldScaleX` instead.
  double get worldScaleX => component.worldScaleX[entity];
  set worldScaleX(double newValue) => component.worldScaleX[entity] = newValue;

  /// `worldScaleY` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.worldScaleY` instead.
  double get worldScaleY => component.worldScaleY[entity];
  set worldScaleY(double newValue) => component.worldScaleY[entity] = newValue;

  /// `worldScaleZ` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.worldScaleZ` instead.
  double get worldScaleZ => component.worldScaleZ[entity];
  set worldScaleZ(double newValue) => component.worldScaleZ[entity] = newValue;

  /// `worldRotationX` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.worldRotationX` instead.
  double get worldRotationX => component.worldRotationX[entity];
  set worldRotationX(double newValue) =>
      component.worldRotationX[entity] = newValue;

  /// `worldRotationY` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.worldRotationY` instead.
  double get worldRotationY => component.worldRotationY[entity];
  set worldRotationY(double newValue) =>
      component.worldRotationY[entity] = newValue;

  /// `worldRotationZ` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.worldRotationZ` instead.
  double get worldRotationZ => component.worldRotationZ[entity];
  set worldRotationZ(double newValue) =>
      component.worldRotationZ[entity] = newValue;

  /// `worldRotationW` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.worldRotationW` instead.
  double get worldRotationW => component.worldRotationW[entity];
  set worldRotationW(double newValue) =>
      component.worldRotationW[entity] = newValue;

  /// `cachedOffsetX` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.cachedOffsetX` instead.
  double get cachedOffsetX => component.cachedOffsetX[entity];
  set cachedOffsetX(double newValue) =>
      component.cachedOffsetX[entity] = newValue;

  /// `cachedOffsetY` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.cachedOffsetY` instead.
  double get cachedOffsetY => component.cachedOffsetY[entity];
  set cachedOffsetY(double newValue) =>
      component.cachedOffsetY[entity] = newValue;

  /// `cachedOffsetZ` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.cachedOffsetZ` instead.
  double get cachedOffsetZ => component.cachedOffsetZ[entity];
  set cachedOffsetZ(double newValue) =>
      component.cachedOffsetZ[entity] = newValue;

  /// `cachedRotationX` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.cachedRotationX` instead.
  double get cachedRotationX => component.cachedRotationX[entity];
  set cachedRotationX(double newValue) =>
      component.cachedRotationX[entity] = newValue;

  /// `cachedRotationY` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.cachedRotationY` instead.
  double get cachedRotationY => component.cachedRotationY[entity];
  set cachedRotationY(double newValue) =>
      component.cachedRotationY[entity] = newValue;

  /// `cachedRotationZ` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.cachedRotationZ` instead.
  double get cachedRotationZ => component.cachedRotationZ[entity];
  set cachedRotationZ(double newValue) =>
      component.cachedRotationZ[entity] = newValue;

  /// `cachedRotationW` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.cachedRotationW` instead.
  double get cachedRotationW => component.cachedRotationW[entity];
  set cachedRotationW(double newValue) =>
      component.cachedRotationW[entity] = newValue;

  /// `cachedScaleX` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.cachedScaleX` instead.
  double get cachedScaleX => component.cachedScaleX[entity];
  set cachedScaleX(double newValue) =>
      component.cachedScaleX[entity] = newValue;

  /// `cachedScaleY` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.cachedScaleY` instead.
  double get cachedScaleY => component.cachedScaleY[entity];
  set cachedScaleY(double newValue) =>
      component.cachedScaleY[entity] = newValue;

  /// `cachedScaleZ` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.cachedScaleZ` instead.
  double get cachedScaleZ => component.cachedScaleZ[entity];
  set cachedScaleZ(double newValue) =>
      component.cachedScaleZ[entity] = newValue;

  /// `cachedParent` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.cachedParent` instead.
  Entity? get cachedParent => component.cachedParent[entity];
  set cachedParent(Entity? newValue) =>
      component.cachedParent[entity] = newValue;
}
