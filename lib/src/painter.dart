import 'package:flutter/widgets.dart';
import 'package:goo2d/goo2d.dart';

class TexturePainter extends CustomPainter {
  final GameTexture texture;
  final FilterQuality filterQuality;

  const TexturePainter(
    this.texture, {
    this.filterQuality = FilterQuality.medium,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final uiImage = texture.image;
    final paint = Paint()..filterQuality = filterQuality;
    canvas.drawImageRect(
      uiImage,
      Rect.fromLTWH(0, 0, uiImage.width.toDouble(), uiImage.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant TexturePainter oldDelegate) {
    return oldDelegate.texture != texture ||
        oldDelegate.filterQuality != filterQuality;
  }
}

/// A stateful widget that renders a [GameSprite] via a [RenderHandle].
///
/// Creates a [RenderHandle] in [State.initState] and disposes it in
/// [State.dispose], ensuring GPU resources (e.g. [FragmentShader]) are
/// properly released when the widget leaves the tree.
///
/// If the [sprite]'s mesh identity changes (via [didUpdateWidget]), the old
/// handle is disposed and a new one is created. For callers that rebuild with
/// a new mesh on every frame, cache the [GameSprite] outside of `build()`.
class SpriteWidget extends StatefulWidget {
  final GameSprite sprite;
  final FilterQuality filterQuality;

  const SpriteWidget(
    this.sprite, {
    super.key,
    this.filterQuality = FilterQuality.medium,
  });

  @override
  State<SpriteWidget> createState() => _SpriteWidgetState();
}

class _SpriteWidgetState extends State<SpriteWidget> {
  late RenderHandle _handle;

  @override
  void initState() {
    super.initState();
    _handle = widget.sprite.mesh.createHandle();
  }

  @override
  void didUpdateWidget(SpriteWidget old) {
    super.didUpdateWidget(old);
    if (!identical(old.sprite.mesh, widget.sprite.mesh)) {
      _handle.dispose();
      _handle = widget.sprite.mesh.createHandle();
    }
  }

  @override
  void dispose() {
    _handle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HandlePainter(_handle, widget.filterQuality),
    );
  }
}

class _HandlePainter extends CustomPainter {
  final RenderHandle handle;
  final FilterQuality filterQuality;

  _HandlePainter(this.handle, this.filterQuality);

  @override
  void paint(Canvas canvas, Size size) {
    handle.render(
      canvas,
      size,
      Paint()..filterQuality = filterQuality,
    );
  }

  @override
  bool shouldRepaint(_HandlePainter old) =>
      old.handle != handle || old.filterQuality != filterQuality;
}
