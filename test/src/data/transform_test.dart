import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/src/data/component.dart';
import 'package:goo2d/src/data/hierarchy/data.dart';
import 'package:goo2d/src/data/object.dart';
import 'package:goo2d/src/data/transform/data.dart';
import 'package:goo2d/src/data/transform/system.dart';
import 'package:goo2d/src/data/world.dart';

(WorldController, TransformSystem) _setup() {
  final world = WorldController();
  final sys = TransformSystem();
  world.addSystem(sys);
  return (world, sys);
}

void _setTransform(TransformData td, int slot, {
  double x = 0, double y = 0, double angle = 0, double sx = 1, double sy = 1,
}) {
  td.x.setSlot(slot, x);
  td.y.setSlot(slot, y);
  td.angle.setSlot(slot, angle);
  td.scaleX.setSlot(slot, sx);
  td.scaleY.setSlot(slot, sy);
}

void main() {
  group('TransformSystem', () {
    test('root entity: world == local after onUpdate', () {
      final (world, sys) = _setup();
      world.createEntityWith([TransformData.new, WorldTransformData.new]);

      final r = (world.query()..withAll(TransformData, WorldTransformData))
          .executeSingle()!;
      final td = r.get<TransformData>();
      final wd = r.get<WorldTransformData>();

      td.x.set(r, 10.0);
      td.y.set(r, 20.0);
      td.angle.set(r, 0.5);
      td.scaleX.set(r, 2.0);
      td.scaleY.set(r, 3.0);

      sys.onUpdate(0);

      expect(wd.wx.get(r),      closeTo(10.0, 1e-5));
      expect(wd.wy.get(r),      closeTo(20.0, 1e-5));
      expect(wd.wAngle.get(r),  closeTo(0.5,  1e-5));
      expect(wd.wScaleX.get(r), closeTo(2.0,  1e-5));
      expect(wd.wScaleY.get(r), closeTo(3.0,  1e-5));
    });

    test('child (depth 1): world pos = parentWorld + rotate(pAngle) * (pScale * localPos)', () {
      final (world, sys) = _setup();

      // Parent at (100, 50), angle=PI/2, scale=(1,1).
      final parent = world.createEntityWith([TransformData.new, WorldTransformData.new]);
      // Child at local (10, 0), angle=0, scale=(1,1).
      final child = world.createEntityWith([
        TransformData.new, WorldTransformData.new, ChildOfData.new,
      ]);

      final pSlot = parent.index;
      final cSlot = child.index;

      final td = (world.query()..withAll(TransformData)).executeSingle()!.get<TransformData>();
      final cd = (world.query()..withAll(ChildOfData)).executeSingle()!.get<ChildOfData>();
      final wd = (world.query()..withAll(WorldTransformData)).executeSingle()!.get<WorldTransformData>();

      _setTransform(td, pSlot, x: 100, y: 50, angle: pi / 2);
      _setTransform(td, cSlot, x: 10);

      cd.parentIndex.setSlot(cSlot, pSlot);
      cd.depth.setSlot(cSlot, 1);

      sys.onUpdate(0);

      // Parent world.
      expect(wd.wx.getSlot(pSlot),     closeTo(100.0, 1e-4));
      expect(wd.wy.getSlot(pSlot),     closeTo(50.0,  1e-4));
      expect(wd.wAngle.getSlot(pSlot), closeTo(pi / 2, 1e-4));

      // Child: rotate local(10,0) by PI/2 → (0,10); add parent pos → (100,60).
      expect(wd.wx.getSlot(cSlot),     closeTo(100.0, 1e-4));
      expect(wd.wy.getSlot(cSlot),     closeTo(60.0,  1e-4));
      expect(wd.wAngle.getSlot(cSlot), closeTo(pi / 2, 1e-4));
    });

    test('grandchild (depth 2): composed through two levels', () {
      final (world, sys) = _setup();

      final gp  = world.createEntityWith([TransformData.new, WorldTransformData.new]);
      final par = world.createEntityWith([TransformData.new, WorldTransformData.new, ChildOfData.new]);
      final ch  = world.createEntityWith([TransformData.new, WorldTransformData.new, ChildOfData.new]);

      final gpSlot = gp.index;
      final pSlot  = par.index;
      final cSlot  = ch.index;

      final td = (world.query()..withAll(TransformData)).executeSingle()!.get<TransformData>();
      final cd = (world.query()..withAll(ChildOfData)).executeSingle()!.get<ChildOfData>();
      final wd = (world.query()..withAll(WorldTransformData)).executeSingle()!.get<WorldTransformData>();

      _setTransform(td, gpSlot);                 // origin
      _setTransform(td, pSlot,  x: 10);          // parent at x=10
      _setTransform(td, cSlot,  x: 5);           // child at local x=5

      cd.parentIndex.setSlot(pSlot, gpSlot); cd.depth.setSlot(pSlot, 1);
      cd.parentIndex.setSlot(cSlot, pSlot);  cd.depth.setSlot(cSlot, 2);

      sys.onUpdate(0);

      expect(wd.wx.getSlot(gpSlot), closeTo(0.0,  1e-4));
      expect(wd.wx.getSlot(pSlot),  closeTo(10.0, 1e-4));
      expect(wd.wx.getSlot(cSlot),  closeTo(15.0, 1e-4));
      expect(wd.wy.getSlot(cSlot),  closeTo(0.0,  1e-4));
    });

    test('markDirty + reparent: next onUpdate reflects new parent', () {
      final (world, sys) = _setup();

      final a     = world.createEntityWith([TransformData.new, WorldTransformData.new]);
      final b     = world.createEntityWith([TransformData.new, WorldTransformData.new]);
      final child = world.createEntityWith([TransformData.new, WorldTransformData.new, ChildOfData.new]);

      final aSlot = a.index;
      final bSlot = b.index;
      final cSlot = child.index;

      final td = (world.query()..withAll(TransformData)).executeSingle()!.get<TransformData>();
      final cd = (world.query()..withAll(ChildOfData)).executeSingle()!.get<ChildOfData>();
      final wd = (world.query()..withAll(WorldTransformData)).executeSingle()!.get<WorldTransformData>();

      _setTransform(td, aSlot);
      _setTransform(td, bSlot, x: 100);
      _setTransform(td, cSlot, x: 5);

      cd.parentIndex.setSlot(cSlot, aSlot);
      cd.depth.setSlot(cSlot, 1);
      sys.onUpdate(0);
      expect(wd.wx.getSlot(cSlot), closeTo(5.0, 1e-4));

      // Reparent to B.
      cd.parentIndex.setSlot(cSlot, bSlot);
      sys.markDirty();
      sys.onUpdate(0);
      expect(wd.wx.getSlot(cSlot), closeTo(105.0, 1e-4));
    });

    test('entity without WorldTransformData is excluded — no crash', () {
      final (world, sys) = _setup();
      // Only TransformData — should not be processed.
      world.createEntityWith([TransformData.new]);
      expect(() => sys.onUpdate(0), returnsNormally);
    });

    test('no entities — no crash', () {
      final (_, sys) = _setup();
      expect(() => sys.onUpdate(0), returnsNormally);
    });
  });
}
