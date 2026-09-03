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

import 'package:goo2d/src/data/camera.dart';
import 'package:goo2d/src/data/transform.dart';
import 'package:goo2d/src/data/world_transform.dart';
import 'package:goo2d/src/render/text_2d.dart';
import 'package:good/good.dart';

/// Camera's columns, one property each - for code
/// touching **one** entity.
///
/// A system walking many resolves the component once per
/// group and indexes the column instead. Every read here is
/// of the published snapshot.
extension Accessor$Camera on Accessor<Camera> {
  /// `cameraZoom` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.cameraZoom` instead.
  double get zoom => component.cameraZoom[entity];
  set zoom(double newValue) => component.cameraZoom[entity] = newValue;

  /// `cameraView` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.cameraView` instead.
  CameraView? get view => component.cameraView[entity];
  set view(CameraView? newValue) => component.cameraView[entity] = newValue;
}

/// Transform2D's columns, one property each - for code
/// touching **one** entity.
///
/// A system walking many resolves the component once per
/// group and indexes the column instead. Every read here is
/// of the published snapshot.
extension Accessor$Transform2D on Accessor<Transform2D> {
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

  /// `transformRotation` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.transformRotation` instead.
  double get rotation => component.transformRotation[entity];
  set rotation(double newValue) =>
      component.transformRotation[entity] = newValue;
}

/// WorldTransform2D's columns, one property each - for code
/// touching **one** entity.
///
/// A system walking many resolves the component once per
/// group and indexes the column instead. Every read here is
/// of the published snapshot.
extension Accessor$WorldTransform2D on Accessor<WorldTransform2D> {
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

  /// `worldRotation` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.worldRotation` instead.
  double get worldRotation => component.worldRotation[entity];
  set worldRotation(double newValue) =>
      component.worldRotation[entity] = newValue;

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

  /// `cachedRotation` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.cachedRotation` instead.
  double get cachedRotation => component.cachedRotation[entity];
  set cachedRotation(double newValue) =>
      component.cachedRotation[entity] = newValue;

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

  /// `cachedParent` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.cachedParent` instead.
  Entity? get cachedParent => component.cachedParent[entity];
  set cachedParent(Entity? newValue) =>
      component.cachedParent[entity] = newValue;
}

/// Text2D's columns, one property each - for code
/// touching **one** entity.
///
/// A system walking many resolves the component once per
/// group and indexes the column instead. Every read here is
/// of the published snapshot.
extension Accessor$Text2D on Accessor<Text2D> {
  /// `textLength` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.textLength` instead.
  int get length => component.textLength[entity];
  set length(int newValue) => component.textLength[entity] = newValue;

  /// `textColor` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.textColor` instead.
  int get color => component.textColor[entity];
  set color(int newValue) => component.textColor[entity] = newValue;

  /// `textCellWidth` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.textCellWidth` instead.
  double get cellWidth => component.textCellWidth[entity];
  set cellWidth(double newValue) => component.textCellWidth[entity] = newValue;

  /// `textCellHeight` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.textCellHeight` instead.
  double get cellHeight => component.textCellHeight[entity];
  set cellHeight(double newValue) =>
      component.textCellHeight[entity] = newValue;

  /// `textLetterSpacing` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.textLetterSpacing` instead.
  double get letterSpacing => component.textLetterSpacing[entity];
  set letterSpacing(double newValue) =>
      component.textLetterSpacing[entity] = newValue;

  /// `textZIndex` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.textZIndex` instead.
  int get zIndex => component.textZIndex[entity];
  set zIndex(int newValue) => component.textZIndex[entity] = newValue;

  /// `textVisible` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.textVisible` instead.
  bool get visible => component.textVisible[entity];
  set visible(bool newValue) => component.textVisible[entity] = newValue;

  /// `textFilter` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.textFilter` instead.
  int get filter => component.textFilter[entity];
  set filter(int newValue) => component.textFilter[entity] = newValue;

  /// `textPivotFractionX` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.textPivotFractionX` instead.
  double get pivotFractionX => component.textPivotFractionX[entity];
  set pivotFractionX(double newValue) =>
      component.textPivotFractionX[entity] = newValue;

  /// `textPivotFractionY` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.textPivotFractionY` instead.
  double get pivotFractionY => component.textPivotFractionY[entity];
  set pivotFractionY(double newValue) =>
      component.textPivotFractionY[entity] = newValue;

  /// `textPivotOffsetX` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.textPivotOffsetX` instead.
  double get pivotOffsetX => component.textPivotOffsetX[entity];
  set pivotOffsetX(double newValue) =>
      component.textPivotOffsetX[entity] = newValue;

  /// `textPivotOffsetY` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.textPivotOffsetY` instead.
  double get pivotOffsetY => component.textPivotOffsetY[entity];
  set pivotOffsetY(double newValue) =>
      component.textPivotOffsetY[entity] = newValue;
}
