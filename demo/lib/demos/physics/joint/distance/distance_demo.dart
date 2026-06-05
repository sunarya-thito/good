import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d_demo/shared/drag_behavior.dart';

class DistanceDemo extends StatefulGameWidget {
  const DistanceDemo({super.key});

  @override
  GameState<DistanceDemo> createState() => _DistanceDemoState();
}

class _DistanceDemoState extends GameState<DistanceDemo> {
  static const _linkColors = [
    Color(0xFFDDDDDD), // static anchor
    Color(0xFFFF6644),
    Color(0xFFFF9944),
    Color(0xFF44AAFF),
    Color(0xFF44DDFF),
  ];

  @override
  Iterable<Widget> build(BuildContext context) sync* {
    // Camera — centered on the chain
    yield GameObjectWidget(
      children: [
        ComponentWidget(
          ObjectTransform.new.withInitialValues(
            (t) => t.position = Vector2(0, 1),
          ),
        ),
        ComponentWidget(
          Camera.new.withInitialValues(
            (c) => c
              ..orthographicSize = 10.0
              ..backgroundColor = const Color(0xFF1A1A2E)
              ..clearFlags = CameraClearFlags.solidColor,
          ),
        ),
      ],
    );

    // Ground
    yield GameObjectWidget(
      children: [
        ComponentWidget(
          ObjectTransform.new.withInitialValues(
            (t) => t.position = Vector2(0, -8),
          ),
        ),
        ComponentWidget(
          Rigidbody.new.withInitialValues(
            (r) => r.bodyType = RigidbodyType.static,
          ),
        ),
        ComponentWidget(
          BoxCollider.new.withInitialValues((c) => c.size = Vector2(22, 1)),
        ),
        ComponentWidget(
          _BoxRenderer.new.withInitialValues(
            (r) => r
              ..color = const Color(0xFF3A3A5A)
              ..width = 22
              ..height = 1,
          ),
        ),
      ],
    );

    // Chain links — yielded top to bottom so GlobalObjectKey entries are
    // registered in order before each successive link's onMounted fires.
    for (var i = 0; i < 5; i++) {
      final y = 6.0 - i * 2.0; // 6, 4, 2, 0, -2
      final isStatic = i == 0;
      final color = _linkColors[i];

      yield GameObjectWidget(
        tag: '_dist_link_$i',
        children: [
          ComponentWidget(
            ObjectTransform.new.withInitialValues(
              (t) => t.position = Vector2(0, y),
            ),
          ),
          ComponentWidget(
            Rigidbody.new.withInitialValues(
              (r) => r.bodyType = isStatic
                  ? RigidbodyType.static
                  : RigidbodyType.dynamic,
            ),
          ),
          ComponentWidget(
            BoxCollider.new.withInitialValues(
              (c) => c.size = Vector2(0.55, 0.55),
            ),
          ),
          if (!isStatic) ...[
            // Pre-declare the joint with fixed 2-unit distance; connectedBody
            // is wired up after mount via _ChainLinkSetup.
            ComponentWidget(
              DistanceJoint.new.withInitialValues(
                (j) => j
                  ..autoConfigureConnectedAnchor = false
                  ..anchor = Vector2.zero()
                  ..connectedAnchor = Vector2.zero()
                  ..autoConfigureDistance = false
                  ..distance = 2.0,
              ),
            ),
            ComponentWidget(
              _ChainLinkSetup.new.withInitialValues(
                (s) => s.prevTag = '_dist_link_${i - 1}',
              ),
            ),
            ComponentWidget(DragBehavior.new),
          ],
          ComponentWidget(
            _BoxRenderer.new.withInitialValues(
              (r) => r
                ..color = color
                ..width = 0.55
                ..height = 0.55,
            ),
          ),
        ],
      );
    }
  }
}

class _ChainLinkSetup extends Behavior with LifecycleListener {
  Object? prevTag;

  @override
  void onMounted() {
    if (prevTag == null) return;
    final prevRb = GameObject.findWithTag(gameObject, prevTag!)?.tryGetComponent<Rigidbody>();
    if (prevRb != null) {
      gameObject.tryGetComponent<DistanceJoint>()?.connectedBody = prevRb;
    }
  }
}

class _BoxRenderer extends Behavior with Renderable {
  Color color = Colors.white;
  double width = 1.0;
  double height = 1.0;

  @override
  void render(Canvas canvas) {
    canvas.drawRect(
      ui.Rect.fromCenter(center: Offset.zero, width: width, height: height),
      Paint()..color = color,
    );
    canvas.drawLine(
      Offset.zero,
      Offset(0, height / 2),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 0.06,
    );
  }
}
