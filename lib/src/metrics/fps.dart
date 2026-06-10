import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class FpsCounter extends SingleChildRenderObjectWidget {
  const FpsCounter({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _FpsCounterRender();
}

int _frames = 0;
int _fps = 0;

int get fps => _fps;

class _FpsCounterRender extends RenderProxyBox {
  late Timer _timer;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _frames = 0;
    _fps = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _fps = _frames;
      _frames = 0;
    });
  }

  @override
  void detach() {
    _timer.cancel();
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    _frames++;
  }
}
