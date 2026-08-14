import 'package:goo/goo.dart';
import 'package:goo/src/animation/struct.dart';
import 'package:goo/src/coroutine/coroutine.dart';

mixin Animations on Coroutines {
  void describeAnimation(AnimationTypeDescriptor descriptor);

  // Animations needs access to Coroutine API (via CoroutineMixin)
  CoroutineFuture startAnimation(
    TimelineAnimation animation,
    List<TimelineDataBinding> bindings,
  );
}

abstract class AnimationTypeDescriptor {
  T has<T extends TimelineStruct>(T struct);
}
