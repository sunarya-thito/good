import 'package:flutter/widgets.dart';

// animation value 0.0→0.5 = curtain closes over old route
// animation value 0.5→1.0 = curtain opens to reveal new route
typedef TransitionOverlayBuilder =
    Widget Function(BuildContext context, Animation<double> animation);

typedef DataWidgetBuilder<W> = Widget Function(BuildContext context, W data);

class GameRoute<T> extends PageRoute<T> {
  GameRoute({
    super.settings,
    super.requestFocus,
    required this.builder,
    this.transitionOverlay,
    this.overlayDuration = const Duration(milliseconds: 600),
    this.maintainState = true,
    super.fullscreenDialog,
    super.allowSnapshotting = true,
  });

  /// Creates a route that defers mounting until [waitFor] resolves, then
  /// passes the resolved value to [builder]. The curtain stays closed until
  /// the future completes.
  static GameRoute<T> withData<T, W>({
    RouteSettings? settings,
    required Future<W> waitFor,
    required DataWidgetBuilder<W> builder,
    TransitionOverlayBuilder? transitionOverlay,
    Duration overlayDuration = const Duration(milliseconds: 600),
    bool maintainState = true,
  }) {
    return _DataGameRoute<T, W>(
      settings: settings,
      waitFor: waitFor,
      dataBuilder: builder,
      transitionOverlay: transitionOverlay,
      overlayDuration: overlayDuration,
      maintainState: maintainState,
    );
  }

  final WidgetBuilder builder;
  final TransitionOverlayBuilder? transitionOverlay;
  final Duration overlayDuration;

  @override
  final bool maintainState;

  @override
  Duration get transitionDuration =>
      transitionOverlay != null ? overlayDuration : Duration.zero;

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final overlay = transitionOverlay;
    if (overlay == null) return child;

    return _CurtainTransition(
      animation: animation,
      overlay: overlay,
      child: child,
    );
  }
}

class _DataGameRoute<T, W> extends GameRoute<T> {
  _DataGameRoute({
    super.settings,
    required Future<W> waitFor,
    required this.dataBuilder,
    super.transitionOverlay,
    super.overlayDuration = const Duration(milliseconds: 600),
    super.maintainState = true,
  }) : _waitFor = waitFor,
       super(builder: _placeholder);

  static Widget _placeholder(BuildContext _) => const SizedBox.shrink();

  final Future<W> _waitFor;
  final DataWidgetBuilder<W> dataBuilder;

  // Always run for overlayDuration regardless of whether there is an overlay.
  @override
  Duration get transitionDuration => overlayDuration;

  @override
  TickerFuture didPush() {
    final result = super.didPush();
    _runWaitFor();
    return result;
  }

  @override
  void didReplace(Route<dynamic>? oldRoute) {
    super.didReplace(oldRoute);
    _runWaitFor();
  }

  Future<void> _runWaitFor() async {
    final ctrl = controller!;
    final half = overlayDuration ~/ 2;
    // super.didPush() already called forward(); cancel it before it ticks
    ctrl.stop();
    await ctrl.animateTo(0.5, duration: half);
    try {
      await _waitFor;
    } finally {
      // always open the curtain, even if the future throws
      await ctrl.animateTo(1.0, duration: half);
    }
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _DeferredPage<W>(future: _waitFor, builder: dataBuilder);
  }
}

class _DeferredPage<W> extends StatefulWidget {
  const _DeferredPage({required this.future, required this.builder});

  final Future<W> future;
  final DataWidgetBuilder<W> builder;

  @override
  State<_DeferredPage<W>> createState() => _DeferredPageState<W>();
}

class _DeferredPageState<W> extends State<_DeferredPage<W>> {
  late W _data;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    widget.future.then((data) {
      if (mounted) {
        setState(() {
          _data = data;
          _ready = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    return widget.builder(context, _data);
  }
}

class _CurtainTransition extends StatefulWidget {
  const _CurtainTransition({
    required this.animation,
    required this.overlay,
    required this.child,
  });

  final Animation<double> animation;
  final TransitionOverlayBuilder overlay;
  final Widget child;

  @override
  State<_CurtainTransition> createState() => _CurtainTransitionState();
}

class _CurtainTransitionState extends State<_CurtainTransition> {
  // New route content hidden until animation ≥ 0.5 (curtain fully closed)
  late CurvedAnimation _content;

  @override
  void initState() {
    super.initState();
    _content = CurvedAnimation(parent: widget.animation, curve: const Threshold(0.5));
  }

  @override
  void didUpdateWidget(_CurtainTransition old) {
    super.didUpdateWidget(old);
    if (old.animation != widget.animation) {
      _content.dispose();
      _content = CurvedAnimation(parent: widget.animation, curve: const Threshold(0.5));
    }
  }

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        // Blocks the route beneath once the transition starts.
        AnimatedBuilder(
          animation: widget.animation,
          builder: (context, _) => AbsorbPointer(
            absorbing: widget.animation.status != AnimationStatus.completed,
            child: const SizedBox.expand(),
          ),
        ),
        // New route content — only interactive once fully revealed.
        AnimatedBuilder(
          animation: widget.animation,
          builder: (context, child) => IgnorePointer(
            ignoring: widget.animation.status != AnimationStatus.completed,
            child: child,
          ),
          child: FadeTransition(opacity: _content, child: widget.child),
        ),
        // Purely visual — never intercepts input.
        Positioned.fill(
          child: IgnorePointer(
            child: widget.overlay(context, widget.animation),
          ),
        ),
      ],
    );
  }
}
