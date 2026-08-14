import 'package:goo/goo.dart';
import 'package:goo/src/animation/animatable.dart';
import 'package:goo/src/coroutine/coroutine.dart';

abstract class TimelineAnimation {}

abstract class TimelineCoroutine {
  Stream call();
}

abstract class TimelineStruct {
  void describeTimeline(TimelineDescriptor desc);
  void describeAnimation(TimelineAnimationDescriptor desc);
}

typedef TimelineLerp<T> = T Function(T a, T b, double t);

// by default, lerp will try to use the `+`, `-`, and `*` operators.
// if the type doesn't support those, user must provide the lerp function
// otherwise it will fallback to a discrete function.

abstract class TimelineDescriptor {
  TimelineData<T> has<T>({TimelineLerp<T>? lerp});
}

abstract class TimelineAnimationDescriptor {
  TimelineAnimation has();
}

class TimelineDataBinding<T> {}

abstract class TimelineOffset {}

// unlike DataPointer, ParamPointer, etc,
// TimelineData does not need to be strict to specific type
abstract class TimelineData<T> {
  TimelineDataBinding<T> bind(DataBinding<T> binding);
}

class ExampleTest extends TimelineStruct {
  late final TimelineData<double> positionX;
  late final TimelineData<double> positionY;

  late final TimelineAnimation toTheLeftAnimation;

  @override
  void describeAnimation(TimelineAnimationDescriptor desc) {
    toTheLeftAnimation = desc.has(); // STILL WORK IN PROGRESS
  }

  @override
  void describeTimeline(TimelineDescriptor desc) {
    positionX = desc.has<double>();
    positionY = desc.has<double>();
  }
}

abstract class Enemy extends EntityStruct
    with Coroutines, Animations, Tickable {
  // right now, EntityStruct is not AnimatableMixin, so we do here, in the future, we can just remove it because EntityStruct will be AnimatableMixin

  late final ExampleTest timeline;

  late final DataPointer<double> positionX;
  late final DataPointer<double> positionY;

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    positionX = data.hasFloat64();
    positionY = data.hasFloat64();
  }

  @override
  void describeAnimation(AnimationTypeDescriptor descriptor) {
    timeline = descriptor.has(ExampleTest());
  }

  void playAnimationExample(Entity entity) {
    startAnimation(timeline.toTheLeftAnimation, [
      timeline.positionX.bind(positionX.bind(entity)),
      timeline.positionY.bind(positionY.bind(entity)),
    ]);
  }

  @override
  void onTick(Duration delta) {}
}
