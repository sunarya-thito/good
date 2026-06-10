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

  void onAttach() {}
  void onDetach() {}
  @override
  void onEvent<T extends EventListener>(Event<T> event) {
    event.dispatch(this as T);
  }

  @override
  Future<void> onEventAsync<T extends EventListener>(AsyncEvent<T> event) {
    return event.dispatch(this as T);
  }

  @override
  bool onDispatchEvent<T extends EventListener>(Event<T> event) {
    if (this is! T) return false;
    event.dispatch(this as T);
    return true;
  }

  @override
  Future<bool> onDispatchEventAsync<T extends EventListener>(
    AsyncEvent<T> event,
  ) async {
    if (this is! T) return false;
    await event.dispatch(this as T);
    return true;
  }
}
