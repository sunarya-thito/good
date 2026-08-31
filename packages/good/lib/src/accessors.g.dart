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

import 'package:good/src/data/hierarchy.dart';
import 'package:good/src/struct.dart';

/// Child's columns, one property each - for code
/// touching **one** entity.
///
/// A system walking many resolves the component once per
/// group and indexes the column instead. Every read here is
/// of the published snapshot.
extension Accessor$Child on Accessor<Child> {
  /// `childParent` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.childParent` instead.
  Entity? get parent => component.childParent[entity];
  set parent(Entity? newValue) => component.childParent[entity] = newValue;

  /// `childNextSibling` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.childNextSibling` instead.
  Entity? get nextSibling => component.childNextSibling[entity];
  set nextSibling(Entity? newValue) =>
      component.childNextSibling[entity] = newValue;

  /// `childPrevSibling` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.childPrevSibling` instead.
  Entity? get prevSibling => component.childPrevSibling[entity];
  set prevSibling(Entity? newValue) =>
      component.childPrevSibling[entity] = newValue;
}

/// Parent's columns, one property each - for code
/// touching **one** entity.
///
/// A system walking many resolves the component once per
/// group and indexes the column instead. Every read here is
/// of the published snapshot.
extension Accessor$Parent on Accessor<Parent> {
  /// `parentFirstChild` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.parentFirstChild` instead.
  Entity? get firstChild => component.parentFirstChild[entity];
  set firstChild(Entity? newValue) =>
      component.parentFirstChild[entity] = newValue;

  /// `parentLastChild` on this entity, from the published snapshot.
  ///
  /// One entity. A system walking many indexes
  /// `component.parentLastChild` instead.
  Entity? get lastChild => component.parentLastChild[entity];
  set lastChild(Entity? newValue) =>
      component.parentLastChild[entity] = newValue;
}
