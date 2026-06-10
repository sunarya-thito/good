import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:goo2d/src/object.dart';
import 'package:goo2d/src/event.dart';
import 'package:goo2d/src/input.dart';
import 'package:goo2d/src/game.dart';
import 'package:goo2d/src/coroutine.dart';
import 'package:goo2d/src/element.dart';
import 'package:meta/meta.dart';

/// A type representing a component that can be lazily or asynchronously loaded.
///
/// This is used by [ComponentWidget] to allow for components that require
/// asset loading (like sprites or sounds) to be defined declaratively.
typedef GameComponent<T extends Component> = FutureOr<ComponentFactory<T>>;

mixin _FakeComponentFuture<T extends Component>
    implements Future<ComponentFactory<T>> {
  T _create();
  @override
  Stream<ComponentFactory<T>> asStream() {
    return Stream.value(_create);
  }

  @override
  Future<ComponentFactory<T>> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) {
    return this;
  }

  @override
  Future<R> then<R>(
    FutureOr<R> Function(ComponentFactory<T> value) onValue, {
    Function? onError,
  }) {
    return Future.value(onValue(_create));
  }

  @override
  Future<ComponentFactory<T>> timeout(
    Duration timeLimit, {
    FutureOr<dynamic> Function()? onTimeout,
  }) {
    return this;
  }

  @override
  Future<ComponentFactory<T>> whenComplete(
    FutureOr<dynamic> Function() action,
  ) {
    action();
    return this;
  }
}

/// A wrapper for a [ComponentFactory] that includes initial parameter configuration.
///
/// This class is used to store both the instantiation logic and the setup
/// logic for a component, allowing it to be passed around and applied later
/// (e.g., during the [ComponentWidget] mounting process).
///
/// ```dart
/// class MyComponent extends Component {
///   double value = 0;
/// }
///
/// void example() {
///   final factory = ComponentFactoryWithParams(
///     MyComponent.new,
///     params: (c) => c.value = 10,
///   );
/// }
/// ```
///
/// See also:
/// * [ComponentFactoryExtension.withInitialValues], the preferred way to create this.
class ComponentFactoryWithParams<T extends Component>
    with _FakeComponentFuture<T> {
  // we implement Future so that we can use FutureOr type-union

  /// The factory function used to instantiate the component.
  ///
  /// This function is stored and executed whenever a new instance of the
  /// component is required by the engine or the widget tree.
  final ComponentFactory<T> factory;

  /// An optional handler used to configure the component immediately after creation.
  ///
  /// If provided, this callback is run before the component is returned by the
  /// factory wrapper, ensuring it is fully initialized with the desired values.
  final ComponentParameterHandler<T>? params;

  /// Creates a factory wrapper with the given [factory] and optional [params].
  ///
  /// * [factory]: The function that creates the component instance.
  /// * [params]: An optional callback for initial configuration.
  ComponentFactoryWithParams(this.factory, {this.params});

  @override
  T _create() {
    final component = factory();
    params?.call(component);
    return component;
  }
}

/// Extension providing fluent configuration for [ComponentFactory] functions.
///
/// This allows for a more readable and declarative syntax when defining
/// components with specific starting values.
extension ComponentFactoryExtension<T extends Component>
    on ComponentFactory<T> {
  /// Returns a factory wrapper that applies the given [params] after instantiation.
  ///
  /// This is commonly used in [ComponentWidget] to configure a component
  /// without needing to create a custom subclass or factory function.
  ///
  /// * [params]: The configuration block to run on the new component.
  ComponentFactoryWithParams<T> withInitialValues(
    ComponentParameterHandler<T> params,
  ) {
    return ComponentFactoryWithParams<T>(this, params: params);
  }
}

/// A function that creates a new instance of a [Component].
typedef ComponentFactory<T extends Component> = T Function();

/// A function used to configure a [Component] instance.
typedef ComponentParameterHandler<T extends Component> =
    void Function(T component);

/// A widget that declaratively adds a [Component] to a [GameObject].
///
/// This widget acts as a bridge between Flutter's reactive UI and Goo2D's
/// imperative entity-component system. When this widget is mounted, it
/// creates the component and adds it to the nearest [GameObject] ancestor.
///
/// ```dart
/// import 'package:vector_math/vector_math_64.dart';
///
/// class PlayerController extends Behavior {}
/// class SpriteComponent extends Component {
///   double opacity = 1.0;
/// }
/// class PhysicsComponent extends Component {
///   Vector2 velocity = Vector2.zero();
/// }
///
/// class MyObject extends StatelessGameWidget {
///   @override
///   Iterable<Widget> build(BuildContext context) => [
///     ComponentWidget(PlayerController.new),
///     ComponentWidget(
///       SpriteComponent.new.withInitialValues((s) => s.opacity = 0.5),
///     ),
///     ComponentWidget(
///       PhysicsComponent.new,
///       update: (p) => p.velocity = Vector2.zero(),
///     ),
///   ];
/// }
/// ```
///
/// See also:
/// * [GameObject], which hosts these components.
/// * [GameEngine], the root of the engine hierarchy.
class ComponentWidget<T extends Component> extends Widget {
  /// The factory or asynchronous future that creates the component instance.
  ///
  /// This can be a simple constructor reference (e.g., `MyComponent.new`) or
  /// a factory wrapped with initial values via [ComponentFactoryExtension].
  final GameComponent<T> factory;

  /// An optional callback to update the component's state during widget rebuilds.
  ///
  /// This is used for reactive synchronization between Flutter's state and the
  /// component's imperative properties (e.g., updating a health bar).
  final ComponentParameterHandler<T>? update;

  /// Creates a [ComponentWidget] that manages a component of type [T].
  ///
  /// * [factory]: The source of the component instance.
  /// * [key]: The standard Flutter widget key.
  /// * [update]: An optional callback run whenever the widget is updated.
  const ComponentWidget(this.factory, {super.key, this.update});

  /// Applies the current [update] handler to the given [component].
  ///
  /// This is called during both the initial registration and subsequent
  /// widget updates to synchronize the component with the widget tree.
  ///
  /// * [component]: The instance to apply updates to.
  T apply(T component) {
    update?.call(component);
    return component;
  }

  @override
  Element createElement() {
    return _ComponentElement(this);
  }
}

class _ComponentRegistration<T extends Component> {
  final T component;
  GameObject? gameObject;
  _ComponentRegistration({required this.component, required this.gameObject}) {
    gameObject?.addComponent(component);
  }

  void reparent(GameObject newGameObject) {
    if (newGameObject == gameObject) return;
    gameObject?.removeComponent(component);
    newGameObject.addComponent(component);
    gameObject = newGameObject;
  }

  void remove() {
    gameObject?.removeComponent(component);
    gameObject = null;
  }
}

class _ComponentElement<T extends Component> extends Element {
  _ComponentElement(ComponentWidget super.widget);

  @override
  ComponentWidget<T> get widget => super.widget as ComponentWidget<T>;

  FutureOr<_ComponentRegistration<T>>? _registration;

  GameObject? _findParentGameObject(Element? parent) {
    if (parent is GameObject) return parent as GameObject;
    if (parent == null) return null;
    GameObject? found;
    parent.visitAncestorElements((element) {
      if (element is GameObject) {
        found = element as GameObject;
        return false;
      }
      return true;
    });
    return found;
  }

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    final gameObject = _findParentGameObject(parent);
    assert(
      gameObject != null,
      'Component $widget must be added to a GameObject.',
    );
    switch (widget.factory) {
      case _FakeComponentFuture<T> withParams:
        _registration = _ComponentRegistration(
          component: widget.apply(withParams._create()),
          gameObject: gameObject!,
        );
        break;
      case Future<ComponentFactory<T>> future:
        _registration = future.then(
          (factory) => _registration = _ComponentRegistration(
            component: widget.apply(factory()),
            gameObject: gameObject!,
          ),
        );
        break;
      case ComponentFactory<T> factory:
        _registration = _ComponentRegistration(
          component: widget.apply(factory()),
          gameObject: gameObject!,
        );
        break;
    }
  }

  @override
  void activate() {
    super.activate();
    assert(
      _registration != null,
      'Component has not been registered previously',
    );
    final gameObject = _findParentGameObject(this);
    assert(
      gameObject != null,
      'Component $widget must be added to a GameObject.',
    );
    switch (_registration) {
      case _ComponentRegistration<T> registration:
        registration.reparent(gameObject!);
        break;
      case Future<_ComponentRegistration<T>> future:
        _registration = future.then((registration) {
          _registration = registration;
          registration.reparent(gameObject!);
          return registration;
        });
        break;
    }
  }

  @override
  void update(covariant ComponentWidget<T> newWidget) {
    super.update(newWidget);
    assert(
      _registration != null,
      'Component has not been registered previously',
    );
    switch (_registration) {
      case _ComponentRegistration<T> registration:
        newWidget.apply(registration.component);
        break;
      case Future<_ComponentRegistration<T>> future:
        _registration = future.then((registration) {
          _registration = registration;
          newWidget.apply(registration.component);
          return registration;
        });
        break;
    }
  }

  @override
  void deactivate() {
    assert(
      _registration != null,
      'Component has not been registered previously',
    );
    switch (_registration) {
      case _ComponentRegistration<T> registration:
        registration.remove();
        break;
      case Future<_ComponentRegistration<T>> future:
        _registration = future.then((registration) {
          _registration = registration;
          registration.remove();
          return registration;
        });
        break;
    }
    super.deactivate();
  }

  @override
  void unmount() {
    assert(
      _registration != null,
      'Component has not been registered previously',
    );
    switch (_registration) {
      case _ComponentRegistration<T> registration:
        registration.remove();
        break;
      case Future<_ComponentRegistration<T>> future:
        _registration = future.then((registration) {
          _registration = registration;
          registration.remove();
          return registration;
        });
        break;
    }
    super.unmount();
  }

  @override
  bool get debugDoingBuild => false;
}

/// A mixin used to identify components that can have multiple instances on a single [GameObject].
///
/// By default, the engine treats components as unique per type on a given
/// object. Adding this mixin allows systems to register and process multiple
/// instances of the same component type (e.g., multiple colliders or audio sources).
mixin MultiComponent on Component {}

/// The base class for all data and logic modules in the Goo2D engine.
///
/// Components are the primary way to add functionality to [GameObject]s.
/// They provide a context-aware environment where logic can access the
/// input system, the game clock, and other components in the hierarchy.
///
/// ```dart
/// class MyComponent extends Component {
///   void doSomething() {
///     print('Attached to object: ${gameObject.name}');
///   }
/// }
/// ```
///
/// See also:
/// * [GameObject], the container for components.
/// * [Behavior], a specialized component for runtime logic.
abstract class Component implements EventListenerMixable {
  GameObject? _gameObject;

  /// The [GameObject] this component is currently attached to.
  ///
  /// Throws an assertion error if the component is not yet attached. Use
  /// [isAttached] or [tryGameObject] if you need to check the status safely.
  GameObject get gameObject {
    assert(_gameObject != null, 'Component is not added to a GameObject');
    return _gameObject!;
  }

  /// Safely returns the [GameObject] this component is attached to, or null.
  ///
  /// Use this when you are unsure if the component has been mounted yet,
  /// avoiding the assertion error thrown by the [gameObject] getter.
  GameObject? get tryGameObject => _gameObject;

  /// Internal method to attach this component to a [GameObject].
  ///
  /// * [gameObject]: The object to attach to.
  @internal
  void internalAttach(GameObject gameObject) {
    _gameObject = gameObject;
  }

  /// Internal method to detach this component from its [GameObject].
  ///
  /// This is called by the engine when a component is removed or its host
  /// object is destroyed, cleaning up the back-reference.
  @internal
  void internalDetach() {
    _gameObject = null;
  }

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
  ) async {
    if (this is! T) return false;
    await event.dispatch(this as T);
    return true;
  }

  /// Whether this component is currently attached to a [GameObject].
  ///
  /// Components are only fully functional when attached, as most of their
  /// properties rely on the [gameObject] context.
  bool get isAttached => _gameObject != null;

  /// The root [GameEngine] instance this component belongs to.
  ///
  /// This provides access to all global systems (input, physics, etc.) and
  /// the main world rendering context.
  GameEngine get game => gameObject.game;

  /// The current state of the keyboard input system.
  ///
  /// Use this to check for key presses, releases, or held states during
  /// the update cycle. Returns null if the input system is not available.
  KeyboardState? get keyboard => game.getSystem<InputSystem>()?.keyboard;

  /// The time elapsed since the last frame, in seconds.
  ///
  /// This should be used to scale movement and animations to ensure they
  /// run at the same speed regardless of the frame rate.
  double get deltaTime => game.getSystem<TickerSystem>()?.deltaTime ?? 0.0;

  /// The total number of frames rendered since the engine started.
  ///
  /// This can be used for simple frame-based timing or to synchronize
  /// logic with specific rendering cycles.
  int get frameCount => game.getSystem<TickerSystem>()?.frameCount ?? 0;

  /// The name of the [GameObject] this component is attached to.
  ///
  /// This is primarily used for debugging and identifying objects in the
  /// scene hierarchy. Names are not guaranteed to be unique.
  String get name => gameObject.name;

  /// Retrieves a specialized state object of type [T] from the [GameObject].
  ///
  /// This is a convenience method for `gameObject.getComponent<T>()`.
  ///
  /// * [T]: The type of the game state component to retrieve.
  T stateObject<T extends GameState>() {
    return gameObject.getComponent<T>();
  }

  /// The tag assigned to the [GameObject] this component is attached to.
  ///
  /// Tags are used for categorizing objects and performing efficient
  /// lookups (e.g., finding all 'enemy' or 'player' objects).
  Object? get tag => gameObject.tag;

  /// Whether the [GameObject] this component is attached to is currently active.
  ///
  /// Inactive objects and their components are typically ignored by the
  /// engine's processing systems (tick, paint, physics).
  bool get active => gameObject.active;

  /// The root [GameObject] of the current scene hierarchy.
  ///
  /// This allows components to navigate to the very top of the entity
  /// tree, regardless of how deep they are nested.
  GameObject get rootObject => gameObject.rootObject;

  /// The parent [GameObject] of the object this component is attached to.
  ///
  /// This will be null if the object is a root object in the game world.
  GameObject? get parentObject => gameObject.parentObject;

  /// An iterable of all child [GameObject]s.
  ///
  /// Use this to iterate through immediate descendants or to perform
  /// searches across the direct children of the object.
  Iterable<GameObject> get childrenObjects => gameObject.childrenObjects;

  /// An iterable of all [Component]s attached to the same [GameObject].
  ///
  /// This provides a low-level way to inspect all functionality currently
  /// assigned to the object.
  Iterable<Component> get components => gameObject.components;

  /// Adds one or more components to the [GameObject] this component is attached to.
  ///
  /// This allows for dynamic expansion of an object's capabilities at runtime.
  /// You can add up to 11 components in a single call.
  ///
  /// * [component]: The primary component to add.
  /// * [a]: Optional second component to add.
  /// * [b]: Optional third component to add.
  /// * [c]: Optional fourth component to add.
  /// * [d]: Optional fifth component to add.
  /// * [e]: Optional sixth component to add.
  /// * [f]: Optional seventh component to add.
  /// * [g]: Optional eighth component to add.
  /// * [h]: Optional ninth component to add.
  /// * [i]: Optional tenth component to add.
  /// * [j]: Optional eleventh component to add.
  void addComponent(
    Component component, [
    Component? a,
    Component? b,
    Component? c,
    Component? d,
    Component? e,
    Component? f,
    Component? g,
    Component? h,
    Component? i,
    Component? j,
  ]) => gameObject.addComponent(component, a, b, c, d, e, f, g, h, i, j);

  /// Removes one or more specific component instances from the [GameObject].
  ///
  /// This is used to strip functionality from an object when it is no longer
  /// needed. You can remove up to 11 components in a single call.
  ///
  /// * [component]: The primary component instance to remove.
  /// * [a]: Optional second component to remove.
  /// * [b]: Optional third component to remove.
  /// * [c]: Optional fourth component to remove.
  /// * [d]: Optional fifth component to remove.
  /// * [e]: Optional sixth component to remove.
  /// * [f]: Optional seventh component to remove.
  /// * [g]: Optional eighth component to remove.
  /// * [h]: Optional ninth component to remove.
  /// * [i]: Optional tenth component to remove.
  /// * [j]: Optional eleventh component to remove.
  void removeComponent(
    Component component, [
    Component? a,
    Component? b,
    Component? c,
    Component? d,
    Component? e,
    Component? f,
    Component? g,
    Component? h,
    Component? i,
    Component? j,
  ]) => gameObject.removeComponent(component, a, b, c, d, e, f, g, h, i, j);

  /// Removes all components of a specific exact type from the [GameObject].
  ///
  /// This is useful for clearing entire categories of functionality (e.g., all
  /// colliders) without having references to the specific instances.
  ///
  /// * [type]: The exact type of components to remove.
  /// * [a]: Optional second type to remove.
  /// * [b]: Optional third type to remove.
  /// * [c]: Optional fourth type to remove.
  /// * [d]: Optional fifth type to remove.
  /// * [e]: Optional sixth type to remove.
  /// * [f]: Optional seventh type to remove.
  /// * [g]: Optional eighth type to remove.
  /// * [h]: Optional ninth type to remove.
  /// * [i]: Optional tenth type to remove.
  /// * [j]: Optional eleventh type to remove.
  void removeComponentOfExactType(
    Type type, [
    Type? a,
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]) =>
      gameObject.removeComponentOfExactType(type, a, b, c, d, e, f, g, h, i, j);

  /// Removes the first component of type [T] from the [GameObject].
  ///
  /// This provides a type-safe way to remove a specific component kind.
  ///
  /// * [T]: The type of component to search for and remove.
  void removeComponentOfType<T extends Component>() =>
      gameObject.removeComponentOfType<T>();

  /// Adds a collection of components to the [GameObject] in bulk.
  ///
  /// Use this when you have a pre-calculated list of components to attach.
  ///
  /// * [components]: The iterable collection of components to add.
  void addComponents(Iterable<Component> components) =>
      gameObject.addComponents(components);

  /// Removes all components matching any of the specified [types] in bulk.
  ///
  /// This is an efficient way to clean up multiple component types at once.
  ///
  /// * [types]: The iterable collection of types to remove.
  void removeComponents(Iterable<Type> types) =>
      gameObject.removeComponents(types);

  /// Sends an event to this object and all of its descendants.
  ///
  /// This is used for broad notifications like "Game Started" or "Level Reset"
  /// that need to be processed by many objects across the hierarchy.
  ///
  /// * [event]: The event to propagate through the hierarchy.
  void broadcastEvent(Event event) {
    gameObject.broadcastEvent(event);
  }

  /// Sends an event to this object only.
  ///
  /// This is used for targeted interactions that should only be handled by the
  /// components on the current [GameObject].
  ///
  /// * [event]: The event to send to the object.
  void sendEvent(Event event) {
    gameObject.sendEvent(event);
  }

  /// Retrieves a component of type [T] from the [GameObject].
  ///
  /// This is used for tight coupling between components on the same object.
  /// Throws an error if the component is not found.
  ///
  /// * [T]: The type of component to retrieve.
  T getComponent<T extends Component>() {
    return gameObject.getComponent<T>();
  }

  /// Safely attempts to retrieve a component of type [T] from the [GameObject].
  ///
  /// Use this for optional features where a component may or may not be present.
  /// Returns null if the component is missing.
  ///
  /// * [T]: The type of component to search for.
  T? tryGetComponent<T extends Component>() {
    return gameObject.tryGetComponent<T>();
  }

  /// Returns all components of type [T] attached to this object.
  ///
  /// This is useful for processing systems that allow multiple instances of
  /// the same component type (see [MultiComponent]).
  ///
  /// * [T]: The type of components to collect.
  Iterable<T> getComponents<T extends Component>() {
    return gameObject.getComponents<T>();
  }

  /// Returns all components of type [T] found in the children of this object.
  ///
  /// This performs a recursive search down the hierarchy, which can be
  /// computationally expensive; use sparingly during gameplay updates.
  ///
  /// * [T]: The type of components to collect from descendants.
  Iterable<T> getComponentsInChildren<T extends Component>() {
    return gameObject.getComponentsInChildren<T>();
  }

  /// Finds the first component of type [T] by searching up the parent hierarchy.
  ///
  /// This is often used by UI or child objects to find their managing systems
  /// or shared state objects in a parent container.
  ///
  /// * [T]: The type of component to search for in ancestors.
  T getComponentInParent<T extends Component>() {
    return gameObject.getComponentInParent<T>();
  }

  /// Safely attempts to find a component of type [T] in the parent hierarchy.
  ///
  /// Returns null if no ancestor contains the requested component type.
  ///
  /// * [T]: The type of component to search for.
  T? tryGetComponentInParent<T extends Component>() {
    return gameObject.tryGetComponentInParent<T>();
  }

  /// Finds the first component of type [T] by searching down the child hierarchy.
  ///
  /// This is a recursive search that returns the first match found in any descendant.
  ///
  /// * [T]: The type of component to search for in descendants.
  T getComponentInChildren<T extends Component>() {
    return gameObject.getComponentInChildren<T>();
  }

  /// Safely attempts to find a component of type [T] in the child hierarchy.
  ///
  /// Returns null if no descendant contains the requested component type.
  ///
  /// * [T]: The type of component to search for.
  T? tryGetComponentInChildren<T extends Component>() {
    return gameObject.tryGetComponentInChildren<T>();
  }

  /// Returns all components of type [T] found in the parent hierarchy.
  ///
  /// This collects matching components from all ancestors up to the root.
  ///
  /// * [T]: The type of components to collect from ancestors.
  Iterable<T> getComponentsInParent<T extends Component>() {
    return gameObject.getComponentsInParent<T>();
  }

  /// Searches for a child [GameObject] with the specified [name].
  ///
  /// This search is non-recursive and only checks the immediate children of the object.
  ///
  /// * [name]: The name of the child object to find.
  GameObject? findChild(String name) {
    return gameObject.findChild(name);
  }

  /// Starts an asynchronous coroutine tied to the lifecycle of this component.
  ///
  /// Coroutines are the preferred way to handle logic that spans multiple
  /// frames (e.g., animations, timers, or scripted sequences).
  ///
  /// * [coroutine]: The function that defines the coroutine logic.
  Future<void> startCoroutine(CoroutineFunction coroutine) {
    return gameObject.startCoroutine(coroutine);
  }

  /// Starts an asynchronous coroutine with initial state data.
  ///
  /// This is useful for reusable coroutines that need external configuration
  /// (e.g., a fade effect that needs a target opacity).
  ///
  /// * [coroutine]: The logic function that accepts the [option].
  /// * [option]: The initial data to pass to the coroutine.
  Future<void> startCoroutineWithOption<T>(
    CoroutineFunctionWithOptions<T> coroutine, {
    required T option,
  }) {
    return gameObject.startCoroutineWithOption<T>(coroutine, option: option);
  }

  /// Cancels a specific running coroutine.
  ///
  /// This stops the coroutine immediately. Use the [Future] returned by
  /// `startCoroutine` to identify the specific routine to stop.
  ///
  /// * [coroutine]: The coroutine future to cancel.
  void stopCoroutine(Future<void> coroutine) {
    gameObject.stopCoroutine(coroutine);
  }

  /// Stops all coroutines currently running on this object.
  ///
  /// You can optionally provide a [coroutine] function reference to stop only
  /// instances of that specific coroutine logic.
  ///
  /// * [coroutine]: An optional filter to stop only specific coroutine types.
  void stopAllCoroutines([Function? coroutine]) {
    gameObject.stopAllCoroutines(coroutine);
  }
}

/// A specialized [Component] designed for runtime game logic.
///
/// Unlike basic components which often just store data, [Behavior]s are
/// typically processed by systems every frame. They include an [enabled]
/// flag to allow toggling their logic without removing them from the object.
///
/// ```dart
/// class MyBehavior extends Behavior {
///   @override
///   void onTick() {
///     if (!enabled) return;
///     // Logic here
///   }
/// }
/// ```
///
/// See also:
/// * [Component], the base class for all modules.
/// * [GameObject.active], which gates the entire object.
abstract class Behavior extends Component {
  /// Whether this behavior's logic should be processed by the engine.
  ///
  /// When set to false, systems will typically skip this behavior during
  /// their update or tick cycles. The component remains attached to the object.
  bool enabled = true;

  @override
  bool onDispatchEvent<T extends EventListener>(Event<T> event) {
    if (!enabled) return false;
    return super.onDispatchEvent(event);
  }

  @override
  FutureOr<bool> onDispatchEventAsync<T extends EventListener>(
    AsyncEvent<T> event,
  ) {
    if (!enabled) return false;
    return super.onDispatchEventAsync(event);
  }
}
