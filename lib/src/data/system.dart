import 'dart:async';

import 'package:goo2d/goo2d.dart';
import 'package:meta/meta.dart';

abstract class WorldSystem implements EventListenerMixable {
  late WorldController _world;
  WorldController get world => _world;

  GameObject? get gameObject => world.gameObject;

  T define<T extends EntityData>(DataFactory<T> factory) {
    return world.ensureDescribed(factory);
  }

  /// Override to declare that this system must be inserted before another type.
  Type? get systemBefore => null;

  /// Override to declare that this system must be inserted after another type.
  Type? get systemAfter => null;

  @internal
  void attachToWorld(WorldController w) => _world = w;

  @override
  void onEvent<T extends EventListener>(Event<T> event) {
    event.dispatch(this as T);
  }

  @override
  FutureOr<void> onEventAsync<T extends EventListener>(AsyncEvent<T> event) {
    return event.dispatch(this as T);
  }

  @override
  bool onDispatchEvent<T extends EventListener>(Event<T> event) {
    if (this is! T) return false;
    event.dispatch(this as T);
    return true;
  }

  @override
  FutureOr<bool> onDispatchEventAsync<T extends EventListener>(
    AsyncEvent<T> event,
  ) {
    if (this is! T) return false;
    final result = event.dispatch(this as T);
    return switch (result) {
      Future<void> f => f.then((_) => true),
      _ => true,
    };
  }
}
