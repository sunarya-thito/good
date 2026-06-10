import 'dart:math';
import 'dart:typed_data';

import 'package:goo2d/goo2d.dart';
import 'package:goo2d/src/data/hierarchy/data.dart';
import 'package:goo2d/src/data/transform/data.dart';

class TransformSystem extends WorldSystem with Tickable {
  // Pre-allocated slot buffers — grown by doubling, never shrunk.
  Int32List _slots = Int32List(64);
  Int32List _depths = Int32List(64);
  int _count = 0;
  bool _dirty = true;

  // Singleton refs cached on first _rebuild(); null until first entity exists.
  late final TransformData _td = define(TransformData.new);
  late final WorldTransformData _wd = define(WorldTransformData.new);
  late final ChildOfData _cd = define(ChildOfData.new);

  /// Call when hierarchy changes: add/remove ChildOfData, change parentIndex or depth.
  void markDirty() => _dirty = true;

  @override
  void onUpdate(double dt) {
    _scan();
    _compute();
  }

  // Scans all entities every frame to detect additions/removals via command buffer.
  // Only re-sorts when markDirty() has been called (hierarchy change).
  void _scan() {
    _count = 0;

    // Roots — entities with TransformData + WorldTransformData but no ChildOfData.
    (world.query()
          ..withAll(_td, _wd)
          ..withNone(_cd))
        .withEntity()
        .forEach((r) {
          _ensure(_count + 1);
          _slots[_count] = r.entity.index;
          _depths[_count] = 0;
          _count++;
        });

    // Children — entities with all three data components.
    (world.query()..withAll(_td, _wd, _cd)).withEntity().forEach((r) {
      _ensure(_count + 1);
      _slots[_count] = r.entity.index;
      _depths[_count] = _cd.depth.getSlot(r.entity.index);
      _count++;
    });

    if (_dirty) {
      _insertionSort();
      _dirty = false;
    }
  }

  void _compute() {
    final td = _td, wd = _wd, cd = _cd;
    for (var i = 0; i < _count; i++) {
      final s = _slots[i];
      if (_depths[i] == 0) {
        final angle = td.angle.getSlot(s);
        final sx    = td.scaleX.getSlot(s);
        final sy    = td.scaleY.getSlot(s);
        final wx    = td.x.getSlot(s);
        final wy    = td.y.getSlot(s);
        wd.wx.setSlot(s, wx);
        wd.wy.setSlot(s, wy);
        wd.wAngle.setSlot(s, angle);
        wd.wScaleX.setSlot(s, sx);
        wd.wScaleY.setSlot(s, sy);
        // Bake affine matrix [a,b,c,d,tx,ty]
        final cosA = cos(angle), sinA = sin(angle);
        final m = wd.matrix.getSlot(s);
        m[0] = cosA * sx;   m[1] = -sinA * sy;
        m[2] = sinA * sx;   m[3] =  cosA * sy;
        m[4] = wx;          m[5] = wy;
      } else {
        final p    = cd.parentIndex.getSlot(s);
        final pwx  = wd.wx.getSlot(p);
        final pwy  = wd.wy.getSlot(p);
        final pwa  = wd.wAngle.getSlot(p);
        final pwsx = wd.wScaleX.getSlot(p);
        final pwsy = wd.wScaleY.getSlot(p);
        final lx   = td.x.getSlot(s);
        final ly   = td.y.getSlot(s);
        final la   = td.angle.getSlot(s);
        final lsx  = td.scaleX.getSlot(s);
        final lsy  = td.scaleY.getSlot(s);
        final cosP = cos(pwa), sinP = sin(pwa);
        final cwx  = pwx + cosP * lx * pwsx - sinP * ly * pwsy;
        final cwy  = pwy + sinP * lx * pwsx + cosP * ly * pwsy;
        final cwa  = pwa + la;
        final cwsx = pwsx * lsx;
        final cwsy = pwsy * lsy;
        wd.wx.setSlot(s, cwx);
        wd.wy.setSlot(s, cwy);
        wd.wAngle.setSlot(s, cwa);
        wd.wScaleX.setSlot(s, cwsx);
        wd.wScaleY.setSlot(s, cwsy);
        // Bake affine matrix using child's world angle (cos/sin of cwa, not pwa)
        final cosC = cos(cwa), sinC = sin(cwa);
        final m = wd.matrix.getSlot(s);
        m[0] = cosC * cwsx;   m[1] = -sinC * cwsy;
        m[2] = sinC * cwsx;   m[3] =  cosC * cwsy;
        m[4] = cwx;           m[5] = cwy;
      }
    }
  }

  void _ensure(int need) {
    if (need <= _slots.length) return;
    final n = need * 2;
    _slots = Int32List(n)..setRange(0, _slots.length, _slots);
    _depths = Int32List(n)..setRange(0, _depths.length, _depths);
  }

  // In-place insertion sort of _slots/_depths pairs by depth ascending.
  void _insertionSort() {
    for (var i = 1; i < _count; i++) {
      final ks = _slots[i];
      final kd = _depths[i];
      var j = i - 1;
      while (j >= 0 && _depths[j] > kd) {
        _slots[j + 1] = _slots[j];
        _depths[j + 1] = _depths[j];
        j--;
      }
      _slots[j + 1] = ks;
      _depths[j + 1] = kd;
    }
  }
}
