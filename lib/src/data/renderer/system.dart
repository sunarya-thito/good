import 'dart:typed_data';
import 'dart:ui';

import 'package:goo2d/goo2d.dart';
import 'package:goo2d/src/data/renderer/data.dart';
import 'package:goo2d/src/data/transform/system.dart';

class RenderSystem extends WorldSystem with Renderable {
  static final Type orderAfter = TransformSystem;

  @override
  Type? get systemAfter => orderAfter;
  final List<GameSprite> sprite;

  RenderSystem(List<GameSprite> sprite) : sprite = List.of(sprite) {
    _handles = List.generate(
      sprite.length,
      (index) => sprite[index].mesh.createHandle(),
    );
  }

  late final List<RenderHandle> _handles;
  late final RenderData _rd = define(RenderData.new);
  late final WorldTransformData _wd = define(WorldTransformData.new);

  static final Uint16List _kQuadIndices =
      Uint16List.fromList([0, 1, 2, 1, 3, 2]);
  static final Float64List _kIdentity4x4 = _makeIdentity();
  static Float64List _makeIdentity() {
    final m = Float64List(16);
    m[0] = m[5] = m[10] = m[15] = 1.0;
    return m;
  }

  @override
  void render(Canvas canvas) {
    (world.query()..withAll(_rd, _wd)).forEach((r) {
      final d = _rd;
      final w = _wd;
      final spriteIdx = d.spriteIndex.get(r);
      final renderSize = d.size.get(r) ??
          (spriteIdx != null ? sprite[spriteIdx].size : const Size(0.5, 0.5));
      final m = w.matrix.get(r); // zero-copy Float32List [a,b,c,d,tx,ty]

      final flipX = d.flipX.get(r);
      final flipY = d.flipY.get(r);

      // Apply flip geometrically (mirrors around entity origin).
      // flipX negates scaleX contribution; flipY negates scaleY contribution.
      final ea = flipX ? -m[0] : m[0];
      final eb = flipY ? -m[1] : m[1];
      final ec = flipX ? -m[2] : m[2];
      final ed = flipY ? -m[3] : m[3];
      final tx = m[4];
      final ty = m[5];

      if (spriteIdx == null) {
        // Debug oval at entity world position.
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(tx, ty),
            width: renderSize.width,
            height: renderSize.height,
          ),
          Paint()
            ..blendMode = d.blendMode.get(r)
            ..filterQuality = d.filterQuality.get(r)
            ..color = d.color.get(r),
        );
        return;
      }

      final sp = sprite[spriteIdx];
      final mesh = sp.mesh;

      // GridMesh: delegate to the handle with the (possibly flip-modified) matrix.
      if (mesh is GridMesh) {
        final handleM = (flipX || flipY)
            ? (Float32List(6)
              ..[0] = ea
              ..[1] = eb
              ..[2] = ec
              ..[3] = ed
              ..[4] = tx
              ..[5] = ty)
            : m;
        _handles[spriteIdx].renderWithMatrix(
          canvas,
          renderSize,
          Paint()
            ..blendMode = d.blendMode.get(r)
            ..filterQuality = d.filterQuality.get(r)
            ..color = d.color.get(r),
          handleM,
        );
        return;
      }

      // SimpleMesh: transform local corners into world space → drawVertices.
      final tex = mesh.texture;
      if (!tex.isLoaded) return;

      final group = UsedTextures.resolveGroup(null, tex);
      final atlasImage = group?.atlasImageFor(tex) ?? tex.image;
      final src = (mesh as SimpleMesh).srcRect ??
          Rect.fromLTWH(0, 0, tex.width.toDouble(), tex.height.toDouble());
      final uvRect = group?.atlasRectFor(tex) ?? src;
      final u0 = uvRect.left, u1 = uvRect.right;
      final v0 = uvRect.top, v1 = uvRect.bottom;

      final sw = renderSize.width, sh = renderSize.height;

      // Local rect: TL(0,0), TR(sw,0), BL(0,sh), BR(sw,sh).
      final positions = Float32List(8);
      positions[0] = tx;                        positions[1] = ty;                       // TL
      positions[2] = ea * sw + tx;              positions[3] = ec * sw + ty;             // TR
      positions[4] = eb * sh + tx;              positions[5] = ed * sh + ty;             // BL
      positions[6] = ea * sw + eb * sh + tx;    positions[7] = ec * sw + ed * sh + ty;   // BR

      final uvs = Float32List(8);
      uvs[0] = u0; uvs[1] = v0; // TL
      uvs[2] = u1; uvs[3] = v0; // TR
      uvs[4] = u0; uvs[5] = v1; // BL
      uvs[6] = u1; uvs[7] = v1; // BR

      final argb = d.color.get(r).toARGB32();
      final colors = Int32List(4);
      colors[0] = colors[1] = colors[2] = colors[3] = argb;

      canvas.drawVertices(
        Vertices.raw(
          VertexMode.triangles,
          positions,
          textureCoordinates: uvs,
          colors: colors,
          indices: _kQuadIndices,
        ),
        BlendMode.modulate,
        Paint()
          ..shader = ImageShader(
            atlasImage,
            TileMode.clamp,
            TileMode.clamp,
            _kIdentity4x4,
          )
          ..filterQuality = d.filterQuality.get(r)
          ..blendMode = d.blendMode.get(r),
      );
    });
  }
}
