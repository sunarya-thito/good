import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

// FPS stat is same across GameEngine instances.
// Except for game fixed ticking, which is only accessible from TickerSystem

class FpsCounter extends SingleChildRenderObjectWidget {
  const FpsCounter({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _FpsCounterRender();
}

bool _fpsHandled = false;
int _frames = 0;
int _fps = 0;

int get fps => _fps;

class _FpsCounterRender extends RenderProxyBox {
  Timer? _timer;
  bool _handleFps = false;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    if (_fpsHandled) return;
    _handleFps = true;
    _fpsHandled = true;
    _frames = 0;
    _fps = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _fps = _frames;
      _frames = 0;
    });
  }

  @override
  void detach() {
    _timer?.cancel();
    _timer = null;
    if (_handleFps) {
      _fpsHandled = false;
      _handleFps = false;
    }
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (_handleFps) {
      _frames++;
    }
  }
}
