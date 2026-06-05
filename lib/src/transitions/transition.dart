import 'package:data_widget/data_widget.dart';
import 'package:flutter/widgets.dart';

class TransitionAnimation {
  // 0.0 - 0.5 = transition in
  // 0.5 - 1.0 = transition out
  // it will stuck at 0.5 until the
  // transition is ready to start out
  final double progress;

  const TransitionAnimation(this.progress);

  double get progressIn => progress.clamp(0.0, 0.5) * 2;
  double get progressOut => (progress - 0.5).clamp(0.0, 0.5) * 2;

  bool get isTransitioningIn => progress <= 0.5;
  bool get isTransitioningOut => progress > 0.5;

  static TransitionAnimation of(BuildContext context) {
    return Data.of<TransitionAnimation>(context);
  }
}

typedef TransitionCallback = Future<void> Function();

class Transition {
  final Widget child;
  final TransitionCallback waitFor;

  const Transition({
    required this.child,
    required this.waitFor,
  });

  factory Transition.inOut({
    required Widget inWidget,
    required Widget outWidget,
    required TransitionCallback waitFor,
  }) {
    return Transition(
      waitFor: waitFor,
      child: Builder(
        builder: (context) {
          final anim = TransitionAnimation.of(context);
          return anim.isTransitioningIn ? inWidget : outWidget;
        },
      ),
    );
  }

  factory Transition.builder({
    required Widget Function(BuildContext, TransitionAnimation) builder,
    required TransitionCallback waitFor,
  }) {
    return Transition(
      waitFor: waitFor,
      child: Builder(
        builder: (context) {
          final anim = TransitionAnimation.of(context);
          return builder(context, anim);
        },
      ),
    );
  }
}
