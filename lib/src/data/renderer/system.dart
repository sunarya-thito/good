import 'dart:ui';

import 'package:goo2d/goo2d.dart';
import 'package:goo2d/src/data/renderer/data.dart';
import 'package:goo2d/src/data/transform/data.dart';
import 'package:goo2d/src/data/transform/system.dart';

class RenderSystem extends WorldSystem with Renderable {
  static final Type orderAfter = TransformSystem;

  @override Type? get systemAfter => orderAfter;
  final List<GameSprite> sprite;

  RenderSystem(List<GameSprite> sprite) : sprite = List.of(sprite);

  late final List<RenderHandle> _handles;
  late final RenderData _rd = define(RenderData.new);
  late final WorldTransformData _wd = define(WorldTransformData.new);

  @override
  void onAttach() {
    super.onAttach();
    _handles = List.generate(
      sprite.length,
      (index) => sprite[index].mesh.createHandle(),
    );
  }

  @override
  void render(Canvas canvas) {
    (world.query()..withAll(_rd, _wd)).forEach((r) {
      final d = _rd;
      final w = _wd;
      final spriteIdx = d.spriteIndex.get(r);
      final paint = Paint()
        ..blendMode     = d.blendMode.get(r)
        ..filterQuality = d.filterQuality.get(r)
        ..color         = d.color.get(r);
      final size = d.size.get(r) ??
          (spriteIdx != null ? sprite[spriteIdx].size : const Size(0.5, 0.5));
      canvas.save();
      canvas.translate(w.wx.get(r), w.wy.get(r));
      canvas.rotate(w.wAngle.get(r));
      canvas.scale(
        w.wScaleX.get(r) * (d.flipX.get(r) ? -1.0 : 1.0),
        w.wScaleY.get(r) * (d.flipY.get(r) ? -1.0 : 1.0),
      );
      if (spriteIdx == null) {
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset.zero, width: size.width, height: size.height),
          paint,
        );
      } else {
        _handles[spriteIdx].render(canvas, size, paint);
      }
      canvas.restore();
    });
  }
}
