import 'package:data_widget/data_widget.dart';
import 'package:flutter/widgets.dart';
import 'package:goo2d/src/transitions/transition.dart';

class TransitionLayer extends StatefulWidget {
  final Widget? child;

  const TransitionLayer({super.key, required this.child});

  @override
  State<TransitionLayer> createState() => _TransitionLayerState();
}

class _TransitionLayerState extends State<TransitionLayer>
    with TickerProviderStateMixin {
  final List<TransitionEntry> _cancelledTransitions = [];
  TransitionEntry? _activeTransition;

  TransitionEntry pushTransition(
    Transition transition, {
    VoidCallback? onComplete,
    VoidCallback? onCancel,
  }) {
    final entry = TransitionEntry._(
      transition,
      AnimationController(vsync: this),
      onComplete: onComplete,
      onCancel: onCancel,
    );
    setState(() {
      if (_activeTransition != null) {
        _activeTransition!._cancelled = true;
        _cancelledTransitions.add(_activeTransition!);
        _activeTransition!.onCancel?.call();
      }
      _activeTransition = entry;
      _runTransition(entry);
    });
    return entry;
  }

  Future<void> _runTransition(TransitionEntry entry) async {
    await entry._animationController.animateTo(0.5);
    await entry.transition.waitFor();
    if (entry.isCancelled) return;
    setState(() {
      _cancelledTransitions.clear();
    });
    await entry._animationController.animateTo(1.0);
    entry.onComplete?.call();
    setState(() {
      _activeTransition = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        if (widget.child != null) widget.child!,
        for (var entry in _cancelledTransitions)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: entry._animationController,
              builder: (context, child) {
                return Data.inherit(
                  data: TransitionAnimation(entry._animationController.value),
                  child: entry.transition.child,
                );
              },
            ),
          ),
        if (_activeTransition != null)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _activeTransition!._animationController,
              builder: (context, child) {
                return Data.inherit(
                  data: TransitionAnimation(
                    _activeTransition!._animationController.value,
                  ),
                  child: _activeTransition!.transition.child,
                );
              },
            ),
          ),
      ],
    );
  }
}

class TransitionEntry {
  final Transition transition;
  bool _cancelled = false;
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;
  final AnimationController _animationController;

  TransitionEntry._(
    this.transition,
    this._animationController, {
    this.onComplete,
    this.onCancel,
  });

  bool get isCancelled => _cancelled;
}

TransitionEntry pushTransition(
  BuildContext context,
  Transition transition, {
  VoidCallback? onComplete,
  VoidCallback? onCancel,
}) {
  return Data.of<_TransitionLayerState>(context).pushTransition(
    transition,
    onComplete: onComplete,
    onCancel: onCancel,
  );
}
